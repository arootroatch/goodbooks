# goodbooks Goals (Sub-project 8) — Design Spec

Date: 2026-10-14
Status: Draft for review
Kaneo: GB-11
Parent spec: `2026-10-05-goodbooks-design.md`. Its cross-cutting rules (§3: money, sign convention, authorization, seeds, testing) apply unchanged. This spec replaces the requirements notes in `docs/roadmap.md` ("Goals (sub-project 8)"). It builds on Personal book (`2026-10-06-goodbooks-tithing-design.md`) and Plaid (`2026-10-08-goodbooks-plaid-design.md`).

## 1. Purpose

Track progress toward money goals in any book, mainly the personal book. There are two kinds of goal. A **payment goal** counts payments matched to it ("pay Uncle Tony back $30,000"). A **savings goal** reads an account's balance, and the goals that share one account fill in priority order ("$6,000 nest egg first, then $10,000 for a truck").

### Understanding from the owner

- Payment goals find their transactions **automatically**, the same way rules auto-categorize: a payee/memo matcher plus an optional amount range. Transactions can also be linked or unlinked by hand.
- The goal link is **independent of categorization**. A payment linked to a goal still goes through the inbox and rules like any other transaction and keeps whatever category it's given. Goals never categorize anything.
- Savings goals use a **live waterfall** over the account's current balance. A withdrawal shrinks the lowest-priority goal first. Nothing is earmarked.
- A met goal stays visible with a "Met" badge until someone archives it by hand. Archived goals move to a Completed list.
- Account balances come from the bank for Plaid accounts. Manual and CSV accounts use an opening balance plus the transactions since.

### Success criteria

1. An editor can create a payment goal with a matcher, and existing matching outflows link to it immediately. New matching transactions from manual entry, CSV import, and Plaid sync link automatically.
2. A transaction counts toward at most one goal. An unlink by hand sticks: the matcher never re-links that transaction.
3. Two savings goals on one account with a balance of $8,000 and targets of $6,000 and $10,000 (in that order) show $6,000 of $6,000 (Met) and $2,000 of $10,000. Reordering them flips the allocation.
4. Plaid accounts show the balance the bank reported at the last sync. A manual or CSV account with an opening balance shows that balance plus the transactions since.
5. The book's Overview, and the household dashboard's Personal section for the personal book, show a goals widget. Each goal opens a report of its transactions.
6. Viewers can see goals but can't change them. People without access to the book see nothing.
7. `demo:seed` shows one payment goal and two savings goals with progress.
8. The PR passes every CI check (Brakeman, bundler-audit, importmap audit, RuboCop, RSpec).

### Out of scope

Earmarked or per-goal contributions; "on track" projections against a target date; incoming-payment goals (money owed *to* the household); savings goals on credit accounts; goals spanning several accounts or books; household-wide goals outside a book; Plaid's `/accounts/balance/get` (balances come only from `/transactions/sync`); balance history snapshots; notifications when a goal is met.

## 2. Approach

Goals are a per-book resource like rules. A payment goal carries its own matcher fields in `Rule`'s vocabulary and is evaluated by the existing `RuleEngine`. A new `GoalMatcher` service runs next to `RuleApplier` at every place new transactions enter the books, and backfills history when a goal's matcher changes. Progress is computed on read by a pure PORO (`Goals::Progress`). Nothing is cached, so the numbers can't drift.

Rejected:
- **A "link to goal" outcome on `Rule`.** Rules are first-match-wins and only touch uncategorized inbox rows. A payment categorized by hand would never link, and a goal would end up tied to a category, which is the coupling the owner ruled out.
- **Manual linking only.** It fails the "matched automatically" requirement.
- **Earmarked savings contributions.** The owner chose the live waterfall instead.

## 3. Data model

### 3.1 `goals` (new)

| Column | Type | Notes |
|---|---|---|
| `business_id` | integer, not null, FK | the book |
| `name` | string, not null | ≤ 100 chars |
| `kind` | string, not null | `payments` \| `savings` |
| `target_cents` | integer, not null | > 0; `money_attribute :target` |
| `position` | integer, not null | priority within the book; set to max + 1 on create, as `Rule` does |
| `target_date` | date, null | displayed only |
| `archived_at` | datetime, null | `Archiving` concern |
| `account_id` | integer, null, FK | savings only; required for savings, must be nil for payments |
| `match_field` | string, null | payments only; `Rule::FIELDS` |
| `match_operator` | string, null | payments only; `Rule::OPERATORS` |
| `match_value` | string, null | payments only; ≤ 100 chars |
| `match_amount_min_cents` | integer, null | payments only; ≥ 0 |
| `match_amount_max_cents` | integer, null | payments only; ≥ 0, ≥ min |

Indexes: `business_id`, `account_id`.

Validations:
- A savings goal's account belongs to the same book, is active, and its kind isn't `credit`.
- A payment goal's matcher is either fully blank (link by hand only) or has field, operator and value all set.
- Matcher fields are cleared on a savings goal, and `account_id` is cleared on a payment goal (`before_validation`, the way `Rule` clears its category for transfers).

Behavior:
- `move_to!(position)` follows `Rule#move_to!`.
- `scope :active`, `scope :ordered`.
- `has_many :transactions, dependent: :nullify`.
- `Goal#matcher?` reports whether all three matcher fields are present.
- `Goal#matcher_description` reads, for example, `payee contains "tony"`, plus the amount range when one is set.
- `RuleEngine.matches?` reads `field`, `operator`, `value`, `amount_min_cents` and `amount_max_cents` from its argument. The goal exposes those through a small value object, `Goal#matcher_rule` (a `Data` with those five members), so `RuleEngine` stays unchanged.

`Business has_many :goals, dependent: :destroy`. `Account has_many :goals, dependent: :restrict_with_error`: an account with savings goals can't be deleted, and accounts are archived, never deleted, anyway.

### 3.2 `transactions` (new columns)

| Column | Type | Notes |
|---|---|---|
| `goal_id` | integer, null, FK, indexed | |
| `goal_linked_by` | string, null | `matcher` \| `user` |

- A linked goal must be a payments goal in the transaction's book.
- `goal_linked_by: "user"` with `goal_id: nil` records a hand unlink; the matcher skips such rows.

### 3.3 `accounts` (new columns)

| Column | Type | Notes |
|---|---|---|
| `opening_balance_cents` | integer, null | manual and CSV accounts; `money_attribute :opening_balance, allow_blank: true` |
| `opening_balance_on` | date, null | required when `opening_balance_cents` is set, and vice versa |
| `reported_balance_cents` | integer, null | Plaid; written by sync |
| `balance_reported_at` | datetime, null | Plaid; written by sync |

`Account#balance_cents`:
- **Plaid:** `reported_balance_cents`, or nil if it hasn't synced since this ships.
- **Manual / CSV:** `opening_balance_cents` + Σ `amount_cents` of non-excluded transactions with `posted_on > opening_balance_on`. Nil when there is no opening balance. Transfers count, because they move real money in and out of the account.

`Account#balance_known?` returns whether `balance_cents` is non-nil.

## 4. Matching (`GoalMatcher`)

`GoalMatcher.new(book).apply(transactions)` returns the number of transactions linked.

- It loads the book's active payments goals that have a matcher, in `position` order.
- **Eligible rows:** `goal_id` nil, `goal_linked_by` nil, not excluded, and `amount_cents < 0` (outflows only).
- The first goal whose `matcher_rule` matches, by `RuleEngine.matches?(goal.matcher_rule, txn.rule_attributes)`, wins. The row gets `goal_id` and `goal_linked_by: "matcher"`.

**Call sites**, next to `RuleApplier` and inside the same DB transaction where there is one:
1. `CsvImport`, on the created rows.
2. `PlaidFeed::Sync`, on the freshly inserted rows.
3. `TransactionsController#create`, on the new transaction.

**Backfill** (`GoalMatcher#rematch(goal)`): runs after a payments goal is created, after its matcher fields or `position` change, and after it's unarchived.
1. Clear `goal_id` and `goal_linked_by` on the goal's rows linked by `matcher`.
2. Run `apply` over every eligible transaction in the book.

Rows linked by `user` are never touched. The controller's flash reports the count: "Goal saved. 7 existing transactions linked."

**Archiving** a goal stops it from matching new rows. Existing links stay, so its report keeps its history. Deleting a goal clears `goal_id` and `goal_linked_by` on its rows linked by `matcher`, through a `before_destroy`, so they become eligible for other goals. Rows linked by `user` keep `goal_linked_by: "user"` and become hand unlinks.

**Manual link and unlink** (editors only):
- The transaction form gets a "Goal" select listing the book's active payments goals, plus "None". Changing it sets `goal_linked_by: "user"`. Choosing "None" on a row that had a goal records a hand unlink.
- The goal report has an "Unlink" button per row (`DELETE /businesses/:business_id/goals/:goal_id/links/:id`, where `:id` is the transaction). It sets `goal_id: nil, goal_linked_by: "user"`.

Bank changes: a goal-linked transaction that Plaid modifies or removes follows the existing sync rules unchanged. An excluded row drops out of the goal's total on its own, so no new review reason is needed.

## 5. Plaid balances

- `PlaidGateway#transactions_sync` adds `accounts:` to each page it returns: an array of `{ account_id:, current_cents: }` built from `accounts[].balances.current`, rounded to cents.
- `FakePlaidGateway` returns the same shape, with configurable balances per account.
- `PlaidFeed::Sync` keeps the `accounts` from the **last** page. Inside its DB transaction, it writes `reported_balance_cents` and `balance_reported_at: Time.current` for each active, assigned account it knows.
- Credit accounts are stored too, as reported, even though no goal reads them.

This amends the Plaid spec's "Out of scope" on balance products. It uses only the balances `/transactions/sync` already returns, not `/accounts/balance/get`.

## 6. Progress (`Goals::Progress`, pure)

`Goals::Progress.for(goals)` returns one `Goals::Progress::Row` per goal, with `goal`, `target_cents`, `saved_cents`, `met?`, `percent` (0–100, floored, capped at 100) and `balance_unknown?`.

- **Payments:** `saved_cents` = −Σ `amount_cents` of the goal's non-excluded transactions, never below 0. A positive amount linked by hand (a refund) reduces it.
- **Savings:** group the active savings goals by account and walk each group in `position` order. `remaining` starts at `max(account.balance_cents, 0)`. Each goal takes `min(target_cents, remaining)`, and `remaining` drops by that amount.
  - When the balance is unknown, every goal on that account has `balance_unknown?` true and `saved_cents` 0.
  - Archived savings goals are left out of the waterfall. The Completed list shows only their target, with no bar.
- `met?` is `saved_cents >= target_cents`.

Payment sums are loaded with one grouped query: `Transaction.where(goal_id: ids, excluded: false).group(:goal_id).sum(:amount_cents)`.

## 7. UI

### 7.1 Navigation and permissions

- Add "Goals" to every book's sidebar after "Rules".
- `GoalsController` and `GoalLinksController` include `BusinessScoped`. Viewers get `index` and `show`; everything else uses `require_editor!`, as `RulesController` does.
- Cross-book IDs (an account, goal, or transaction from another book) give 404.
- The personal book follows its existing membership rules. No `BusinessKindOnly`.

### 7.2 Goals page (`GET /businesses/:business_id/goals`)

- Active goals in `position` order. Each row shows the name, the kind, a progress bar with "$12,000 of $30,000", a "Met" badge when met, and the target date when set.
  - Payment goals show their matcher description, or "Linked by hand".
  - Savings goals show their account. On an unknown balance they show "Set an opening balance" (manual/CSV, linking to the account form) or "Waiting for the bank's balance" (Plaid).
- Editors get drag-to-reorder, reusing the rules list's Stimulus controller and `PATCH …/move`.
- A "Completed" section lists archived goals, with "Unarchive".
- "New goal" opens a form with a kind radio. A small Stimulus toggle shows the matcher fields for payments and the account select for savings. The account select lists active non-credit accounts in the book.

### 7.3 Goal report (`GET /businesses/:business_id/goals/:id`)

The widget's click-through. The header shows the progress bar, the target, the target date, and for editors Edit / Archive.

- **Payments:** a table of linked transactions, oldest first: date, payee, account, amount, and a running total (saved so far). Editors get "Unlink" per row. Excluded rows are not shown.
- **Savings:**
  - The allocation for the goal's account: every active savings goal on it, in order, with its share, and the current one highlighted.
  - The account's transactions, newest first: date, payee, amount, and the balance after each row. For manual/CSV accounts the list goes back to `opening_balance_on`, with the balance running forward from the opening balance. For Plaid accounts it covers the last 12 months, with the balance worked backwards from the reported balance.
  - Excluded rows are not shown and don't affect the balance.

### 7.4 Widget (`goals/_widget` partial)

- One card titled "Goals" with a compact row per active goal: name, thin bar, "$x of $y", and a Met badge. Each row links to the goal's report.
- Rendered on the book's Overview (`businesses#show`). On the household dashboard it appears in the Personal section only, for the personal book.
- Not rendered when the book has no active goals.
- `HouseholdDashboard` exposes `goals` (the progress rows for the personal book).

### 7.5 Accounts

- The account form for manual and CSV accounts gets "Opening balance" and "As of" fields.
- Plaid accounts show "Balance $X · reported <relative time>" read-only.
- The accounts index gets a Balance column, which is blank when unknown.

### 7.6 Transactions

- The transaction form gets the "Goal" select (§4).
- The transactions list shows a small goal tag on linked rows.

## 8. Components summary

| Component | Kind | Responsibility |
|---|---|---|
| `Goal` | model | validations, ordering, archive, matcher value object |
| `GoalMatcher` | service | link eligible transactions; backfill on goal change |
| `Goals::Progress` | PORO | targets, saved amounts, waterfall |
| `Account#balance_cents` | model method | balance by source |
| `PlaidGateway` / `FakePlaidGateway` | gateway | return `accounts` balances on sync pages |
| `PlaidFeed::Sync` | service | store reported balances; call `GoalMatcher` |
| `CsvImport`, `TransactionsController#create` | existing | call `GoalMatcher` |
| `GoalsController` | controller | CRUD, move, archive/unarchive, report |
| `GoalLinksController` | controller | unlink a transaction |
| `goals/_widget` | partial | Overview and dashboard widget |

## 9. Error handling

- Invalid goal forms re-render with errors (422), as rules do.
- If a backfill fails, the goal save rolls back with it: the save and `rematch` run in one transaction.
- A Plaid page without `accounts` (older fake fixtures) leaves the balances unchanged.
- Progress never raises on a missing balance; it reports `balance_unknown?`.

## 10. Testing

RSpec, following the parent spec's §3 testing rules.

- **Model:**
  - `Goal`: kind-specific validations, same-book account, non-credit account, `move_to!`, `matcher_rule`, `before_destroy` reset.
  - `Account#balance_cents` for all three sources, unknown cases, excluded rows, posted-on-the-opening-date exclusion.
  - The `Transaction` goal-link validation.
- **`Goals::Progress`:**
  - The waterfall: $8,000 with $6,000 and $10,000 targets → $6,000 met and $2,000.
  - A withdrawal shrinks the last goal; a negative balance → zero; an unknown balance.
  - Payment sums with a refund and with an excluded row; percent caps at 100.
- **`GoalMatcher`:**
  - Outflows only; first goal by position wins; skips archived goals and goals without a matcher.
  - Respects hand unlinks and hand links; `rematch` clears and relinks only `matcher` rows; the amount range.
- **Integration points:**
  - CSV import links goals.
  - `PlaidFeed::Sync` links goals and stores reported balances from the last page.
  - Manual create links goals.
- **Requests:**
  - Viewers can't create, update, move, archive, or unlink.
  - Non-members get 404.
  - Cross-book account, goal, or transaction IDs are rejected.
- **System:**
  1. Create a "Tony" payment goal → existing payments are linked (flash count) → the Overview widget shows progress → the report lists them with a running total → Unlink one → the total drops, and re-saving the goal doesn't re-link it.
  2. Two savings goals on one account → the widget shows the waterfall → reordering on the Goals page flips the allocation.

## 11. Demo seed

In the personal book:
- **"Pay back Uncle Tony":** a $30,000 payment goal, with matcher `payee contains "tony"` and a handful of seeded payments to "Tony Russo" totaling $12,000.
- **"Nest egg" ($6,000) then "Truck" ($10,000):** both on the personal savings account. The account has an opening balance (manual/CSV), or a fake Plaid reported balance, of $8,000.

## 12. Parent spec and roadmap amendments

- **Roadmap:** the Goals row points at this spec, and the "Goals (sub-project 8)" notes are replaced by a link here. The open questions are resolved as follows:
  1. Balances come from both sources (§3.3, §5).
  2. Goals don't categorize (§1).
  3. A transaction belongs to at most one goal (§3.2).
  4. Savings use a live waterfall (§6).
  5. Met goals stay visible until archived by hand (§1).
  6. Goals follow the book's permissions (§7.1).
- **Plaid spec, Out of scope:** balances returned by `/transactions/sync` are now stored (§5).
