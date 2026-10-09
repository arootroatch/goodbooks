# goodbooks Plaid (Sub-project 5) — Design Spec

Date: 2026-10-08
Status: Draft for review
Kaneo: GB-5
Parent spec: `2026-10-05-goodbooks-design.md` §8 (this document refines and supersedes it). The parent's cross-cutting rules (§3: money, sign convention, authorization, seeds, testing) apply unchanged. Builds on Invoices (`2026-10-06-goodbooks-invoices-design.md`) and Personal book (`2026-10-06-goodbooks-tithing-design.md`).

## 1. Purpose

Bring bank and card activity in automatically. A book owner connects a bank through Plaid Link, assigns each of its accounts to a book (a business or the personal book), and from then on posted transactions arrive daily, on Plaid's webhook, or on demand, and are categorized by the existing rules.

### Understanding from the owner

- Some accounts already have CSV history in goodbooks. Linking such a bank must not duplicate that history: a Plaid account can be **attached to an existing account**, and from then on both sources feed it.
- **CSV upload stays available** on Plaid-fed accounts as a fallback (for a bank outage or a month Plaid missed), and the two sources dedupe against each other.
- The personal book's joint checking account is fed by Plaid too.

### Success criteria

1. With `PLAID_*` configured, a book owner can connect a bank, assign each account (new account in a book, attach to an existing account, or skip), and see transactions arrive.
2. Overlap between Plaid and existing CSV or manual rows does not create duplicates in either direction.
3. Bank-side edits and removals are applied, except where they would undo the user's work; those rows are flagged for review in the inbox instead.
4. Syncs run daily, on the `SYNC_UPDATES_AVAILABLE` webhook, and from a "Sync now" button, with retries; a bank that needs re-authentication shows a banner and can be reconnected in place.
5. Webhooks are accepted only with a valid Plaid signature.
6. Without `PLAID_*` configured, no Plaid UI or route is reachable, and the app behaves exactly as before.
7. All tests run without network access; `demo:seed` shows a connected bank without network access.
8. The PR passes every CI check (Brakeman, bundler-audit, importmap audit, RuboCop, RSpec).

### Out of scope

Investment, liability, and balance products; Plaid's own categories and the personal finance category taxonomy; recurring-transaction APIs; pending transactions (only posted ones are imported); multiple households; a Plaid "Sync now" for all items at once.

## 2. Approach

A thin gateway (`PlaidGateway`) over the official `plaid` gem, swapped for `FakePlaidGateway` in tests and demo through configuration. All bank-to-books logic lives in one service (`Plaid::Sync`) built from small pure pieces: a mapper (Plaid transaction → attributes) and a claim matcher (Plaid row ↔ existing row). Plaid identity is a separate column from the CSV identity, so one row can carry both, which is what lets the two sources dedupe against each other.

Rejected: storing Plaid's `transaction_id` in `external_id` (the parent's design; a CSV row and its Plaid twin can't both keep their identity, so whichever source arrives second duplicates); deduping on payee (Plaid normalizes merchant names, so `SQ *JOES COFFEE 8475` and `Joe's Coffee` never match); a per-account cutoff alone (can't handle CSV uploaded after Plaid has synced).

## 3. Data model

```
PlaidItem    household, created_by (user), institution_name, item_id (unique), access_token (encrypted),
             cursor (nullable), status: ok|login_required|error (default ok), last_synced_at, last_error,
             has_many accounts (nullify on destroy)
Account      + plaid_item_id (nullable FK), + plaid_account_id (string, unique where not null),
             + plaid_mask (nullable), + plaid_name (nullable; the account name as Plaid reports it),
             + plaid_sync_from (date, nullable)
             source enum unchanged: manual|csv|plaid
Transaction  + plaid_transaction_id (string, nullable)  unique(account, plaid_transaction_id) where not null
             + review_reason: removed_by_bank|changed_by_bank (string, nullable)
```

- `PlaidItem#access_token` uses Active Record Encryption (`encrypts :access_token`), is never rendered, and is excluded from `inspect` (`self.filter_attributes`). `access_token` is covered by the existing `:token` filter parameter.
- An item's accounts may belong to different books. A Plaid account the owner skipped has no `Account` row; the item keeps the list of Plaid accounts by asking the gateway when the assignment page opens.
- **Assigned accounts** are `Account` rows with `plaid_item_id` and `plaid_account_id` set and `source: plaid`.
- **Read-only fields move from per-account to per-row**: a transaction's date, amount, and payee are read-only when it has `external_id` or `plaid_transaction_id` (`Transaction#imported?`). A manual row on an attached account stays editable. `TransactionsController` and the form use `imported?` instead of `account.manual?`; new manual transactions are still only offered on manual accounts.

## 4. Gateway

`PlaidGateway` (`app/models/plaid_gateway.rb`, not `Plaid::Client`, which collides with the gem's namespace) wraps a `Plaid::PlaidApi` built from `PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ENV` (`sandbox`|`production`):

| Method | Plaid endpoint | Returns |
|---|---|---|
| `create_link_token(user:, access_token: nil)` | `/link/token/create` (products `transactions`, `webhook` = `https://APP_HOST/plaid/webhooks`; update mode when `access_token` given) | link token string |
| `exchange_public_token(public_token)` | `/item/public_token/exchange` | `{access_token, item_id}` |
| `institution_name(access_token)` | `/item/get` + `/institutions/get_by_id` | string |
| `accounts(access_token)` | `/accounts/get` | array of `{account_id, name, mask, type, subtype}` |
| `transactions_sync(access_token, cursor)` | `/transactions/sync` (count 500) | `{added, modified, removed, next_cursor, has_more}` |
| `item_remove(access_token)` | `/item/remove` | nil |
| `webhook_verification_key(kid)` | `/webhook_verification_key/get` | JWK hash |

- Returns plain hashes and structs, never gem model objects, so the fake matches exactly.
- Errors are translated: `ITEM_LOGIN_REQUIRED` → `PlaidGateway::LoginRequired`; `TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION` → `PlaidGateway::MutationDuringPagination`; rate limits, 5xx, timeouts, and errors Plaid marks retryable → `PlaidGateway::TransientError`; anything else → `PlaidGateway::Error` with Plaid's `error_code` and `error_message`.
- `PlaidGateway.enabled?` is true only when all three env vars are present. `Rails.configuration.x.plaid_gateway` holds the instance in use; the test environment and `demo:seed` set it to `FakePlaidGateway`.
- `FakePlaidGateway` (`lib/fake_plaid_gateway.rb`, required by the spec support and by the demo seeder; never loaded in production) keeps items, accounts, scripted sync pages, and scripted errors in memory, and signs webhooks with a test EC key whose JWK it serves from `webhook_verification_key`.

## 5. Linking and managing items

### 5.1 Who

- **Link**: any user who is `owner` of at least one book (business or personal).
- **Assign**: to books the user owns.
- **Manage an item** (assign remaining accounts, Sync now, reconnect, remove): the item's `created_by` user and the household owner.
- Everyone else: 404 on item pages. Viewers and editors of a book see Plaid status (institution, last synced, status) on its accounts list, read-only.

### 5.2 Flow

1. **Connect a bank** (`GET /plaid_items/new`): the page fetches a link token and renders a Stimulus controller (`plaid-link`) that loads `https://cdn.plaid.com/link/v2/stable/link-initialize.js` (Plaid requires loading from its CDN; the app has no CSP today, and if one is added it must allow `cdn.plaid.com`). On Link success it posts `public_token` to `POST /plaid_items`.
2. **Create**: exchange the token, look up the institution name, create the `PlaidItem`, redirect to assignment.
3. **Assign** (`GET /plaid_items/:id/assignment`): one row per Plaid account (Plaid name, mask, type) with a choice:
   - **Skip** (default for accounts not yet assigned);
   - **New account in [book]**: name defaults to `plaid_name`, kind inferred (depository checking → checking, savings → savings, credit → credit, else other);
   - **Attach to [book › account]**: manual or CSV accounts (not archived, no Plaid link) in books the user owns. Attaching sets `source: plaid` and `plaid_sync_from` (default: the account's latest `posted_on`, editable in the row; blank allowed).
   Already-assigned accounts show their assignment read-only. `PATCH /plaid_items/:id/assignment` applies all rows in one DB transaction, then enqueues a sync.
4. **Item page** (`GET /plaid_items/:id`): institution, status, last synced, last error, assigned accounts, and buttons Sync now, Reconnect (when `login_required` or `error`), Assign accounts, Remove.
5. **Remove** (`DELETE /plaid_items/:id`): resets each account first, inside one DB transaction: it goes back to `csv` if it has a CSV mapping, else `manual`; `plaid_item_id`, `plaid_account_id`, and `plaid_sync_from` are cleared; transactions keep everything, including `plaid_transaction_id`. The item row is destroyed. Then `item_remove` is called (a failure is shown but does not undo the local removal). **Known limitation, accepted:** rows keep their old Plaid IDs, so if the same bank is connected again (Plaid issues new IDs) those rows are not claim candidates, and rows on or after the new connection's sync-from date may duplicate; the user excludes them by hand.
6. **Connections list** (`GET /plaid_items`): items the user can manage, plus a "Connect a bank" button for book owners. Linked from settings navigation when Plaid is enabled.

## 6. Sync

### 6.1 Mapping (`Plaid::TransactionMapper`, pure)

From a Plaid transaction hash to attributes:
- `posted_on` = `date` (the posted date).
- `amount_cents` = `-(BigDecimal(amount.to_s) * 100).to_i` after checking it is a whole number of cents (Plaid outflows are positive; the app's are negative). A non-whole value raises, so it surfaces as a sync error rather than silently rounding.
- `payee` = `merchant_name` if present, else `name` (squished; "Unknown" if both are blank).
- `memo` = `name` when `merchant_name` was used and differs from it, else nil.
- `pending: true` → skipped (returns nil). When a pending transaction posts, Plaid sends a new `added` with a new `transaction_id`, which is imported normally; removals of pending IDs find no row and are ignored.

### 6.2 Claiming (`Plaid::ClaimMatcher`, pure)

Given incoming rows and candidate existing rows (both as structs of id/key, posted_on, amount_cents), pairs them one-to-one: same `amount_cents`, `|posted_on difference| ≤ 3 days`, nearest date first, then lowest id. Each candidate is used at most once per call. The same matcher serves both directions (§6.4, §7).

### 6.3 `Plaid::Sync.call(item, gateway:)`

1. **Fetch**: call `transactions_sync` from the stored cursor until `has_more` is false, accumulating `added`, `modified`, `removed`. On `MutationDuringPagination`, discard the accumulation and restart from the stored cursor (at most 3 restarts, then raise as transient).
2. **Apply**, in one DB transaction, then save `cursor = next_cursor`, `last_synced_at`, `status: ok`, `last_error: nil`. Any exception rolls back and leaves the cursor unchanged.
3. **added** (per assigned account; Plaid accounts with no `Account` row are ignored):
   - mapped row nil (pending) → skip;
   - `posted_on < plaid_sync_from` → skip;
   - `plaid_transaction_id` already present in the account → treat as modified;
   - else claim: candidates are the account's rows with `plaid_transaction_id IS NULL` and `posted_on` within ±3 days of any incoming row. A claimed row gets `plaid_transaction_id` set and nothing else changes (its date, amount, payee, category, and links stay as the user knew them);
   - else insert with `plaid_transaction_id`.
   - `RuleApplier.new(book).apply(inserted)` runs per book on the inserted rows only.
4. **modified**: find by `plaid_transaction_id`. Skip if not found or `excluded`. Otherwise assign date and amount; never overwrite payee or memo (users' text); if the row is invalid (for example, a linked invoice deposit whose amount would fall below its allocations), discard the changes and set `review_reason: "changed_by_bank"` instead.
5. **removed**: find by `plaid_transaction_id`. If the row has invoice payments or `categorized_by: "user"`, set `review_reason: "removed_by_bank"`; otherwise set `excluded: true`.
6. Returns a result (inserted, claimed, modified, flagged, excluded counts) for the flash and logs.

Row writes use `update!`/`create!` so model validations and guards apply; the only expected validation failure (step 4) is handled explicitly, and anything else aborts the sync.

### 6.4 Job

`PlaidSyncJob.perform_later(item)`:
- `limits_concurrency to: 1, key: ->(item) { item }` so two syncs of one item never overlap.
- `retry_on PlaidGateway::TransientError, wait: :polynomially_longer, attempts: 5`.
- `PlaidGateway::LoginRequired` → `status: login_required`, `last_error` set, no retry.
- `PlaidGateway::Error` → `status: error`, `last_error` set, no retry.
- Skips items whose status is `login_required` (a reconnect clears it).

Triggers:
- **Daily**: `config/recurring.yml` production entry `plaid_sync` at 4am, command `PlaidItem.sync_all_later`, which enqueues every item not in `login_required`, guarded by `PlaidGateway.enabled?`.
- **Webhook**: `TRANSACTIONS` / `SYNC_UPDATES_AVAILABLE`.
- **Sync now**: `POST /plaid_items/:id/sync` (manager only), flash "Sync started".

## 7. CSV import on Plaid-fed accounts

`CsvImport::Preview` gains a third duplicate class. After exact matching on `external_id`, rows whose hash is not present are claim-matched (§6.2) against the account's rows that have a `plaid_transaction_id` and no `external_id`. Matched rows:
- appear in the preview as **"Already synced from bank"** with the matched row's date, payee, and amount;
- are skipped on commit, and the commit writes the CSV row's `external_id` onto the matched row (in the same DB transaction), so a later re-import of the same file finds exact duplicates.

The preview's existing counts gain `synced_count` (stored on `CsvImport` as a new integer column, default 0).

## 8. Review

- A transaction with `review_reason` set shows in a **"Needs review"** section at the top of the business inbox and the household inbox (same access filtering as the inbox), regardless of its category. Each row: date, account, payee, amount, category, the reason ("Removed by the bank" / "The bank changed this transaction; your version was kept"), and two buttons:
  - **Exclude** → `excluded: true`, `review_reason: nil` (blocked with the existing message if it has invoice payments; the user unlinks first);
  - **Keep** → `review_reason: nil`.
- `PATCH /businesses/:business_id/transactions/:id/review` with `decision=exclude|keep`, editor or above, Turbo removes the row.
- The transaction list gains a "Needs review" filter. The dashboard shows a count of rows needing review per book when non-zero.

## 9. Webhooks

`POST /plaid/webhooks` (`Plaid::WebhooksController`):
- Skips authentication, the setup redirect, and CSRF. `rate_limit to: 60, within: 1.minute`.
- **Verification** (`Plaid::WebhookVerifier`, given the raw body, the `Plaid-Verification` header, a key fetcher, and now):
  1. decode the JWT header without verifying; `alg` must be `ES256`, `kid` present;
  2. fetch the JWK for `kid` (cached in `Rails.cache` for 1 hour; a key with `expired_at` set is rejected);
  3. verify the signature with the `jwt` gem (`algorithms: ["ES256"]`);
  4. `iat` must be no more than 5 minutes before now;
  5. `request_body_sha256` must equal the SHA-256 hex of the raw body (constant-time compare).
  Any failure → 401 with an empty body, logged at info without the token.
- **Handling** (after verification, by `item_id`; unknown items → 200 and ignored):
  - `TRANSACTIONS` / `SYNC_UPDATES_AVAILABLE` → enqueue `PlaidSyncJob`;
  - `ITEM` / `ERROR` with `ITEM_LOGIN_REQUIRED`, and `ITEM` / `PENDING_EXPIRATION` or `PENDING_DISCONNECT` → `status: login_required`;
  - `ITEM` / `LOGIN_REPAIRED` → `status: ok`, enqueue a sync;
  - anything else → 200, ignored.
- New dependencies: `plaid` and `jwt` gems, pinned in the Gemfile, both passing bundler-audit.

## 10. Re-authentication

- An item with `status: login_required` shows a banner on the dashboard and the item page: "Your connection to INSTITUTION needs to be renewed. [Reconnect]" (managers only; others see the text without the button).
- Reconnect opens Link in update mode (`create_link_token(access_token:)`). On success, the item's status becomes `ok` and a sync is enqueued; no token exchange is needed.

## 11. Configuration and deployment

- Env: `PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ENV`. Documented in the README (with Plaid's sandbox credentials flow) and listed, commented out, in `docker-compose.yml`.
- `APP_HOST` (already required) builds the webhook URL.
- With Plaid disabled: navigation hides it, every Plaid route returns 404 (including webhooks), the recurring entry does nothing, and existing Plaid accounts keep their data and show "Plaid is not configured" on the item page.

## 12. Components summary

| Unit | Kind | Responsibility |
|---|---|---|
| `PlaidGateway` | adapter | the only code that talks to Plaid |
| `FakePlaidGateway` | test/demo double | scripted items, pages, errors, signed webhooks |
| `Plaid::TransactionMapper` | pure | Plaid transaction → attributes |
| `Plaid::ClaimMatcher` | pure | one-to-one fuzzy pairing |
| `Plaid::WebhookVerifier` | pure (key fetcher injected) | JWT and body-hash verification |
| `Plaid::Sync` | service | apply a sync to the books |
| `Plaid::Assignment` | service | apply assignment rows (new / attach / skip) |
| `PlaidSyncJob` | job | concurrency, retries, status |
| `PlaidItem` | model | item state |
| `PlaidItemsController`, `PlaidAssignmentsController`, `TransactionReviewsController`, `Plaid::WebhooksController` | controllers | screens and endpoints |
| `plaid_link_controller.js` | Stimulus | open Link, post the result |

## 13. Error handling

- Gateway failures in interactive actions (link token, exchange, accounts, remove) → flash with Plaid's message; nothing half-created (exchange and item creation happen together; if account lookup fails, the item exists and the assignment page offers "Try again").
- Sync failures → item status and `last_error`, shown on the item page; the cursor is unchanged.
- A Plaid account that disappears from `/accounts/get` → its `Account` stays, flagged on the item page as "No longer reported by the bank".
- Assigning to a book the user doesn't own, or attaching an account that is archived, already Plaid-linked, or in another book → 404 or a row error, nothing applied.
- Webhook verification failure → 401; webhook for an unknown item → 200.

## 14. Testing

TDD throughout; clean output; WebMock keeps all real HTTP blocked.

- **Pure specs**: `TransactionMapper` (sign inversion, cents precision, non-whole cents raises, merchant_name vs name, memo rule, pending skipped); `ClaimMatcher` (exact day, ±3 boundary, 4 days apart no match, nearest wins, tie → lowest id, one-to-one with two identical amounts, empty inputs); `WebhookVerifier` with real ES256 keys generated in the spec (valid; wrong alg; missing kid; bad signature; `iat` 6 minutes old; body tampered; expired key).
- **Gateway spec**: WebMock-stubbed Plaid HTTP for each method, including error translation, so `PlaidGateway` itself is covered without the network.
- **`Plaid::Sync` specs** (with `FakePlaidGateway`): insert; pending skipped; cutoff; claim of a CSV row (identity set, fields untouched); claim of a manual row; modified applied; modified on an excluded row ignored; modified rejected by the linked-deposit guard → flagged; removed untouched → excluded; removed user-categorized → flagged; removed with invoice payments → flagged; rules applied to inserted rows only, per book (an item spanning a business and the personal book); pagination; mutation restart; failure leaves cursor unchanged.
- **CSV specs**: preview marks "Already synced from bank"; commit writes the hash onto the Plaid row; re-import is an exact duplicate.
- **Job specs**: transient retry; login required → status, no retry; concurrency key; login_required items skipped.
- **Request specs**: standard matrix for items, assignment, sync, review; assigning to a non-owned book → 404; attach validations; manager-only actions; everything 404 when Plaid is disabled; webhook 401/200 cases and the enqueued job; `imported?` read-only rule (manual row on an attached account stays editable).
- **System spec** (`js: true`): the `plaid-link` controller is given a fake Link (a test-only `window.Plaid` stub injected by the spec) that immediately succeeds; assign one new account and attach one existing; Sync now; the inbox shows new rows and a claimed CSV row isn't duplicated; a needs-review row is kept with one click.

## 15. Demo seed

`demo:seed` (with `FakePlaidGateway`, no network):
- one "Demo Bank" item created by the owner, holding the owner's business checking (new), a business credit card (new), and the personal book's Joint Checking (attached to the existing CSV account with `plaid_sync_from` two weeks before its last row);
- about 3 months of synced transactions, some rule-categorized, with the overlapping fortnight claimed rather than duplicated;
- one row flagged `removed_by_bank` (user-categorized) so the review section is visible;
- the item `ok` with `last_synced_at` recent.

## 16. Parent spec amendments

In `2026-10-05-goodbooks-design.md`:
- §5.4: "Imported transactions (CSV, Plaid): date, amount, and payee are read-only" now applies per row (`external_id` or `plaid_transaction_id` present), not per account.
- §8: replace with a pointer to this spec and a one-paragraph summary (gateway name, `plaid_transaction_id` beside `external_id`, claiming in both directions, `review_reason`, personal-book assignment, attach-to-existing, CSV kept on Plaid accounts).

In `docs/roadmap.md`: sub-project 5's Design and Documents rows point here; the hand-offs "flag, don't exclude, a removed transaction that has invoice payments" and "allow linking Plaid accounts to the personal book" are satisfied by §6.3 and §5.
