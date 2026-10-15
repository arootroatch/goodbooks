# goodbooks Sharing Polish (Sub-project 7) — Design Spec

Date: 2026-10-14
Status: Draft for review
Kaneo: GB-7
Parent spec: `2026-10-05-goodbooks-design.md`. Its cross-cutting rules (§3: money, sign convention, authorization, seeds, testing) apply unchanged. This spec refines and partly supersedes the parent's §10 ([§14](#14-parent-spec-and-roadmap-amendments) lists the changes).

## 1. Purpose

The household shares goodbooks with a spouse and an accountant. Sharing polish makes that safe to keep running: every user can see and end their own logins, the household owner can cut someone off completely, and the owner can always answer "who changed this, and what was it before?" It also adds the minimum operational visibility a self-hosted app needs: unhandled errors are recorded where the owner can see them, and container logs stop growing forever.

### Understanding from the owner

- **No email.** Invites stay copy-link. Sending email only for invites isn't worth SMTP setup, a mailer and a job, so email delivery is dropped from this sub-project (not deferred to another).
- **The audit log records people's edits only.** A change is logged when a signed-in person made it. Plaid sync, background jobs and other system work are not logged. When a person's single action sets off a bulk change (applying rules to the inbox, committing a CSV import, reordering), it is logged as **one summary event**, not one event per row.
- **Removing someone deactivates their login.** "Remove from household" deletes their memberships, ends their sessions, and blocks sign-in. The user row is kept so the audit log still shows their name.
- **Error log and Docker log rotation** were added to this sub-project during design. Failed-job visibility and a sign-in event log were considered and left out.

### Success criteria

1. Every user can open **Sessions** and see each of their active sessions with device, IP, signed-in time and last-seen time, the current one marked. They can revoke any one, or every session except the current one. A revoked session's next request goes to the sign-in page.
2. The household owner can open **Users**, see every user's book access and last activity, sign a user out everywhere, remove a user from the household, and reactivate a removed user. A removed user cannot sign in, and their old cookies don't work.
3. The household owner can't remove themselves, another household owner, or anyone who is the last owner of a book.
4. Creating, updating or deleting any covered record ([§6.3](#63-covered-models)) through the app writes one `AuditEvent` with the actor, the record, and the changed attributes before and after. Secrets are never stored.
5. Applying rules, committing a CSV import, creating a book and reordering rules or goals each write one summary event and no per-row events. Plaid sync and other background jobs write none.
6. The household owner can open **Audit log** and filter it by user, record type, book and date range. Nobody can edit or delete an audit event.
7. An unhandled exception in a request or a job appears on the owner's **Errors** page, grouped with earlier occurrences of the same error, and can be marked resolved.
8. `docker-compose.yml` rotates the app's logs.
9. `demo:seed` shows several sessions, audit events and one error.
10. The PR passes every CI check (Brakeman, bundler-audit, importmap audit, RuboCop, RSpec).

### Out of scope

Email of any kind (invites, alerts, password reset); a sign-in or security-event log (failed logins, 2FA failures, rate-limit hits); a UI for failed Solid Queue jobs; audit visibility for book owners; reverting a change from the audit log; audit retention or export; error notifications; error log retention; deleting user rows.

## 2. Approach

**Audit capture is a model concern.** `Audited` adds `after_create`, `after_update` and `after_destroy` callbacks to each covered model. They write an `AuditEvent` from `saved_changes` (or the destroyed record's attributes) when there is an actor ([§6.1](#61-the-actor)) and no summary block is open. Writing inside the record's transaction means a rolled-back save leaves no event. Every write path is covered, including ones added later, without anyone remembering to call a logger. Background jobs have no actor, so they're skipped without special cases.

**Sessions** extend the Rails 8 generator's `Session` with `last_seen_at`. **Deactivation** is a timestamp on `User`, checked at sign-in and on every cookie lookup.

**Errors** are captured with a `Rails.error` subscriber, which Rails already calls for unhandled exceptions in requests and jobs.

Rejected:
- **Explicit `AuditEvent.record!` calls in controllers.** About 40 controllers; one missed call is a silent gap.
- **The `audited` or `paper_trail` gem.** It's a new dependency, and summary blocks and actor overrides would still be custom code on top.
- **Logging system changes with a "system" actor.** Plaid sync alone would bury people's edits.
- **Deleting removed users.** The audit log would lose its link to who did what.

## 3. Data model

### 3.1 `sessions` (new column)

| Column | Type | Notes |
|---|---|---|
| `last_seen_at` | datetime, null | set at creation; refreshed by `resume_session` at most once every 5 minutes (`Session::TOUCH_INTERVAL`) |

The migration backfills `last_seen_at = updated_at`.

### 3.2 `users` (new column)

| Column | Type | Notes |
|---|---|---|
| `deactivated_at` | datetime, null | set by "Remove from household"; cleared by "Reactivate". Scopes `User.active` and `User.deactivated` |

### 3.3 `audit_events` (new)

| Column | Type | Notes |
|---|---|---|
| `user_id` | integer, not null, FK | the actor |
| `action` | string, not null | `create` \| `update` \| `destroy` \| `summary` |
| `auditable_type` | string, null | model class name; null for some summaries |
| `auditable_id` | integer, null | no FK, so it survives deletion |
| `business_id` | integer, null | the book, when the record has one ([§6.4](#64-book-and-label)); no FK, so it survives deletion |
| `label` | string, not null | what the record was called when the event was written, e.g. "Invoice #1042" or "Rule: payee contains STRIPE" |
| `changed_values` | json, not null, default `{}` | `{ "attr" => [before, after] }`; `[value, nil]` pairs on destroy, `[nil, value]` on create |
| `summary` | string, null | the sentence for summary events; null otherwise |
| `created_at` | datetime, not null | no `updated_at` |

Indexes: `created_at`, `(user_id, created_at)`, `(auditable_type, auditable_id)`, `(business_id, created_at)`.

`AuditEvent` is read-only after create: `readonly?` returns `true` for persisted rows, and `before_destroy` raises. There are no update or destroy routes.

### 3.4 `error_events` (new)

| Column | Type | Notes |
|---|---|---|
| `fingerprint` | string, not null, unique | SHA-256 of the error class and its first backtrace line under `app/` (or the first line, if none) |
| `error_class` | string, not null | |
| `message` | text, not null | truncated to 1,000 characters |
| `backtrace` | text, not null | the first 30 lines, `Rails.backtrace_cleaner`-cleaned |
| `source` | string, null | the request's `controller#action` or the job class, when known |
| `occurrences` | integer, not null, default 1 | |
| `first_seen_at` | datetime, not null | |
| `last_seen_at` | datetime, not null | |
| `last_user_id` | integer, null | the actor at the latest occurrence, if any; no FK |
| `resolved_at` | datetime, null | cleared when the error recurs |

## 4. Sessions

### 4.1 Tracking

- `start_new_session_for` sets `last_seen_at` to now.
- `find_session_by_cookie` rejects (and destroys) a session whose user is deactivated, as it already does for expired sessions.
- After a session resumes, it is touched if `last_seen_at` is older than `Session::TOUCH_INTERVAL` (5 minutes). The touch uses `update_column`, so it doesn't change `updated_at` and doesn't write an audit event.
- `Session#device_label` turns the user agent into "Browser on OS" (e.g. "Safari on iOS", "Firefox on Windows") using a few regexes in a small `UserAgentLabel` PORO. Unknown parts read "Unknown browser" or "unknown OS". A blank user agent reads "Unknown device".

### 4.2 Sessions page (`GET /sessions`, `SessionsListController#index`)

- Every signed-in user, for their own sessions only. Linked from the user menu in the sidebar as **Sessions**.
- A table sorted by `last_seen_at`, newest first, with columns Device, IP address, Signed in and Last seen. The current session shows a "This device" badge and no revoke button.
- `DELETE /sessions/:id` revokes one of the user's own sessions. Another user's session id returns 404.
- `DELETE /sessions/others` revokes every one of the user's sessions except the current one. The button shows only when there are others.

The existing singular `resource :session` (sign in / sign out) is unchanged. The list lives in its own controller so it doesn't mix with sign-in.

## 5. Users (household owner)

### 5.1 Users page (`GET /users`, `UsersController#index`)

- Household owner only (`require_household_owner!`). Linked from the sidebar next to Invites as **Users**. The name keeps it apart from the existing **People** page (`/people`), which manages taxpayer `Person` records and is unchanged.
- Active users first, then deactivated users in their own section. Each active user shows:
  - name, email and a "Household owner" badge where it applies
  - each book they belong to, with their role there
  - last seen (the newest `last_seen_at` across their sessions, or "Never")
  - two actions: **Sign out everywhere** and **Remove from household**
- Deactivated users show when they were removed and a **Reactivate** action.

### 5.2 Actions

All three actions go through confirm dialogs and are `PATCH`es on member routes of `resources :users, only: :index`.

- **Sign out everywhere** (`PATCH /users/:id/sign_out`). Destroys all of the user's sessions. Used on yourself, it ends the current session too and goes to the sign-in page.
- **Remove from household** (`PATCH /users/:id/deactivate`). Everything happens in one transaction, with the user's book rows locked:
  1. Refuse if the target is the current user or any household owner.
  2. Refuse if the target is the last owner of any book. The flash names the books: "Alex is the last owner of Smith Photography. Make someone else an owner first."
  3. Destroy their memberships (each writes an audit event).
  4. Destroy their sessions.
  5. Set `deactivated_at`.
  6. Revoke any of their usable invites (set `expires_at` to now), so they can't grant themselves access again.

  It writes one summary event: "Removed Alex from the household".
- **Reactivate** (`PATCH /users/:id/reactivate`). Clears `deactivated_at` and writes a summary event. It doesn't restore memberships; the owner sends a new invite for that.

### 5.3 Sign-in and invites

- `SessionsController#create` treats a deactivated user's correct password exactly like a wrong one: same message, and the attempt counts against the rate limit. The 2FA step also refuses a deactivated pending user.
- Accepting an invite while signed in as a deactivated user can't happen, because their session is rejected. The sign-up form on an invite rejects a deactivated user's email with the existing "already taken" error. The owner reactivates first.
- A deactivated user's `Person` link is untouched.

## 6. Audit log

### 6.1 The actor

`Current` gains `audit_actor`, an override, and `Current.actor` returns `audit_actor || user`.

- **Requests:** the actor is the signed-in user.
- **`Audit.as(user) { ... }`** sets the override for the block. It's used where a person acts before they have a session: accepting an invite while signing up, and `/setup` creating the household, its first user and their books (the actor is the new owner).
- **Background jobs** have no session and no override, so they write nothing. `Current` is reset between jobs, as Rails already does.

### 6.2 `Audited` concern

```ruby
class Rule < ApplicationRecord
  include Audited
  audited label: -> { "Rule: #{field} #{operator} #{value}" }, business: :business
end
```

- **`after_create`, `after_update`, `after_destroy`** call `Audit.record(self, action)`. It returns without writing if there's no actor or a summary block is open.
- **An update writes nothing when only ignored attributes changed**, such as a touch of `updated_at`.
- **What's stored:** `changed_values` comes from `saved_changes` minus the ignored attributes: `id`, `created_at`, `updated_at`, plus anything the model lists in `audited ignore: [...]`. Money columns are stored as integer cents and formatted on display.
- **Secrets are never stored.** Any attribute whose name matches `Audit::SECRETS` (`digest`, `token`, `secret`, `otp`, `password`, `crypt`, `salt`) is stored as `"[FILTERED]"`, both before and after. That covers `token_digest` and `access_token`, for example. `config.filter_parameters` isn't reused because it also matches `email` and `code`, which aren't secrets from the household owner. A spec asserts that no covered model can store an unfiltered secret column.
- **`label:`** is a lambda evaluated on the record. Without one, the label is `"#{model_name.human} ##{id}"`.
- **`business:`** names the association, or a lambda, that gives the book ([§6.4](#64-book-and-label)).
- **Child records:** `InviteGrant` changes are folded into the parent invite's event. `Invite` serializes its grants as a `grants` attribute (e.g. `["Smith Photography: editor"]`) on create and destroy, and `InviteGrant` is not audited on its own.

### 6.3 Covered models

| Area | Models |
|---|---|
| Books and people | `Business`, `Person`, `Membership`, `Invite` (with grants), `Household` |
| Money in and out | `Account`, `Transaction`, `Category`, `Rule`, `MileageEntry` |
| Invoices | `Client`, `Invoice`, `InvoicePayment` |
| Sales tax | `SalesTaxProfile`, `SalesTaxFiling` |
| Tax engine | `TaxYear`, `HomeOffice`, `PersonAdjustment`, `EstimatedPayment`, `TaxParameters` |
| Goals and Plaid | `Goal`, `PlaidItem` |

Not covered: `User` and `Session` (their security changes are shown on the Sessions and Users pages, and their columns are mostly secrets); `CsvImport` (covered by its summary); Active Storage tables; `InviteGrant` (folded into `Invite`); `AuditEvent` and `ErrorEvent` themselves.

`PlaidItem`'s sync bookkeeping (`last_synced_at`, `last_error`, `status`, cursor) is written by jobs, which have no actor. When a person re-links or removes an item, the event records that action, and `access_token` is filtered.

### 6.4 Book and label

The `business_id` stored on an event comes from:
- `business_id` directly, for models that have it
- `account.business_id`, for `Transaction`
- `invoice.business_id`, for `InvoicePayment`
- the record's own id, for `Business`

Records with no single book (`Household`, `Person`, `Invite`, `TaxYear`, `PersonAdjustment`, `EstimatedPayment`, `TaxParameters`, `PlaidItem`) store null and appear only under "All books".

The label is stored when the event is written, so deleted or renamed records still read the way they did at the time.

### 6.5 Summary blocks

```ruby
Audit.summarize(business: @business) { |summary| count = RuleApplier.new(@business).apply(rows); summary.text = "Applied rules: #{count} transactions categorized" }
```

- Inside the block, `Audited` callbacks don't write. When the block finishes, one `summary` event is written with `summary.text`, plus `auditable_type`/`auditable_id` if the block set them. Nothing is written if the block raises, or if there's no actor.
- Blocks nest. Only the outermost writes, and an inner block's text is dropped.

Wrapped call sites:

| Action | Summary text |
|---|---|
| Rules → Apply to inbox (`RulesController#apply`) | "Applied rules: 12 transactions categorized" |
| CSV import commit (`CsvImportsController#commit`) | "Imported 42 transactions into Checking (3 duplicates skipped)" |
| Creating a book (`BusinessProvisioner`, `PersonalBookProvisioner`) | "Created book Smith Photography" (one event, not one per category and cash account) |
| Rule reorder (`Rule.reorder`) | "Reordered rules" |
| Goal reorder (`Goal.reorder`) | "Reordered goals" |
| Saving a payments goal whose matcher changed | the goal's own `update` event, written normally. The rematch uses `update_columns`, so it writes nothing |
| Remove from household / Reactivate | [§5.2](#52-actions) |

Reorders use `update_all`, which skips callbacks. The summary is their only record.

Transaction edits that run `GoalMatcher` or `RuleApplier` on a single row inline (manual entry) are not wrapped. They produce the transaction's own events, which is what a person did.

### 6.6 Audit log page (`GET /audit`, `AuditEventsController#index`)

- Household owner only. Linked from the sidebar near Settings as **Audit log**.
- Filters (GET form, `DateRangeParams` for dates):
  - **User:** any user, including deactivated ones
  - **Record type:** the covered models, by human name
  - **Book:** any book, or "All books"
  - **Date range**
- Newest first, 50 per page with Newer / Older links. Uses keyset pagination on `(created_at, id)`, so no new gem is needed.
- **Each row shows:**
  - the time, the actor's name and the action ("created", "updated", "deleted", or the summary text)
  - the label, linked to that record's full history (the same page filtered to the record); it works even after the record is deleted
  - the book name
- **Expanding a row** (`<details>`) shows a before → after table. Money columns are formatted as dollars and booleans as Yes/No; `[FILTERED]` is shown as is.
- **A record's history:** `GET /audit?auditable_type=Invoice&auditable_id=7`. The page doesn't add history links on record pages; that's a possible follow-up.

## 7. Error log

### 7.1 Capture

- `ErrorLog` subscribes to `Rails.error` in an initializer (`Rails.error.subscribe(ErrorLog.new)`). It records reports with `handled: false`, plus explicit reports with `severity: :error`, and skips warnings.
- **It skips exceptions Rails turns into 4xx responses:** `ActiveRecord::RecordNotFound`, `ActionController::RoutingError`, `ActionController::InvalidAuthenticityToken`, `ActionController::ParameterMissing` and `ActionController::BadRequest`, plus anything in `ActionDispatch::ExceptionWrapper.rescue_responses`.
- **A new fingerprint** creates a row. **A repeat** increments `occurrences`, updates `last_seen_at`, `message`, `source` and `last_user_id`, and clears `resolved_at`.
- **Written directly.** Unhandled exceptions reach the subscriber after the request's or job's transactions have unwound, so a plain write sticks. A report made explicitly inside a transaction that later rolls back is lost with it. That's acceptable: the app makes no such reports today. A second connection isn't an option, because SQLite would block on the open write lock.
- **It never raises.** Any failure inside the subscriber is rescued and sent to `Rails.logger.error` only.
- **Request params, headers and cookies are never stored.** `source` comes from the `controller` and `action`, or `job`, in the report's context.

### 7.2 Errors page (`GET /errors`, `ErrorEventsController#index`)

- Household owner only. Linked from the sidebar under Audit log as **Errors**, with a count badge of unresolved errors when there are any.
- Two tabs, **Open** and **Resolved**, each sorted by `last_seen_at`, newest first. Each row shows the class, message, source, occurrence count, and first and last seen.
- Expanding a row shows the backtrace.
- `PATCH /errors/:id/resolve` and `PATCH /errors/:id/reopen` toggle `resolved_at`. Error events can't be deleted from the UI.

## 8. Docker log rotation

`docker-compose.yml` gains, on the `app` service:

```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
```

The README's operations section notes the 50 MB cap and that `docker compose logs` shows only what's kept.

## 9. Navigation and permissions

| Page | Who | Sidebar |
|---|---|---|
| Sessions | every user, own sessions | user menu |
| Users (`/users`) | household owner | Settings group |
| Audit log | household owner | Settings group |
| Errors | household owner | Settings group, with an unresolved count |

Non-owners get 403 from Users, Audit log and Errors, matching `require_household_owner!`. Book owners do not see audit events for their books.

## 10. Components summary

| Component | Kind | Purpose |
|---|---|---|
| `Audited` | model concern | callbacks, `audited` macro |
| `Audit` | module | `record`, `as`, `summarize`, attribute filtering |
| `AuditEvent` | model | read-only event row, filter scopes |
| `AuditEventsController` + view | controller | audit log page |
| `UserAgentLabel` | PORO | device label |
| `SessionsListController` + view | controller | own sessions, revoke |
| `UsersController` + view | controller | Users page, sign out, deactivate, reactivate |
| `User::Deactivation` | PORO | the §5.2 rules and transaction, returning a result with an error message |
| `ErrorLog` | `Rails.error` subscriber | capture |
| `ErrorEvent` | model | grouped error row |
| `ErrorEventsController` + view | controller | errors page |

## 11. Error handling

- **Deactivating a protected user** (yourself, a household owner, the last owner of a book) redirects back to Users with the reason in a flash alert. Nothing changes.
- **A user revoking their current session through `DELETE /sessions/:id`** is treated as sign-out.
- **Audit writes run inside the record's transaction.** If one fails (it shouldn't), the user's save fails too, rather than leaving the change unaudited.
- **Error capture failures** are logged and swallowed ([§7.1](#71-capture)).

## 12. Testing

TDD throughout, following the parent spec's §3.

**Model specs**
- **`Audited`, against a few representative models:**
  - create, update and destroy events with the right `changed_values`
  - no event with no actor, and none for an ignored-only change
  - filtered secrets
  - the stored label and book
  - an `Invite` event carries its grants
- **`Audit.summarize`:** one event, no per-row events, nesting, nothing written on raise, nothing without an actor
- **`Audit.as`:** the override applies only inside the block
- **Coverage:** every model in §6.3 includes `Audited`; no other model does unless it's added to the table
- **`AuditEvent`:** can't be updated or destroyed
- **`UserAgentLabel`:** a table of real user agents
- **`User::Deactivation`:** each refusal rule, the full happy path, invites revoked
- **`ErrorLog`:** grouping by fingerprint, recurrence reopens, skipped 4xx exceptions, never raises

**Request specs**
- **Authorization:** 403 for non-owners on Users, Audit log and Errors; another user's session returns 404
- **Sessions:** a revoked session's cookie redirects to sign-in; a deactivated user's cookie and password are both refused; `last_seen_at` is throttled
- **Summaries:** rules apply, CSV commit and provisioning each write exactly one summary
- **Jobs:** `PlaidSyncJob` with the fake gateway writes no audit events

**System specs**
- revoke another session
- remove a user from the household, then confirm they can't sign in
- filter the audit log and expand a row
- resolve an error

## 13. Demo seed

`demo:seed` adds:
- a second session for the owner (a phone user agent, last seen yesterday)
- about 15 audit events across users, books and record types, including a summary and a destroy
- one open error event

It does this through `Audit.as` and the real models, not hand-built rows, except for the error event.

## 14. Parent spec and roadmap amendments

- **Parent §10** gets a note: "Refined and superseded by `2026-10-14-goodbooks-sharing-polish-design.md`. Email delivery was dropped. Removing a user deactivates their login. The audit list was updated to the current models, and an error log was added."
- **Parent §5.3** gets its last bullet ("Email delivery arrives in sub-project 7") replaced with "Invites are copy-link only; email delivery was dropped (sharing polish spec §1)."
- **Parent §5.10:** the mention of `SMTP_*` env vars is removed.
- **Roadmap:**
  - row 7's Contents become "session management, household user removal (deactivation), audit log, error log, Docker log rotation", its Design links this spec, and its Status becomes Specced
  - the Documents table links this spec
  - the "Sharing polish comes last" note no longer mentions email delivery
