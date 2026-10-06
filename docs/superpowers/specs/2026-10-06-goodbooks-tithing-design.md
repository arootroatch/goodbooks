# goodbooks Personal Book + Tithing — Design Spec

Date: 2026-10-06
Status: Draft for review
Kaneo: GB-9
Parent spec: `2026-10-05-goodbooks-design.md`. This document amends parent §1 (see §9) and slots in after Invoices, before Sales tax. The parent's cross-cutting rules (§3: money, sign convention, authorization, seeds, testing) apply unchanged.

## 1. Purpose

Give the household a book for its joint personal checking account: import it, categorize personal spending, and track the weekly tithe. Each week, 10% of the tithable income that came into the account is owed; tithe payments (mostly cashed checks) going out of the account pay it down. The tithe page answers "how far ahead or behind are we?"

### Understanding from the owner

- The joint account holds personal activity only. Business income reaches it as owner draws transferred from the business accounts.
- Every deposit is tithable by default. The owner can mark deposits as not tithable (refunds, moves from savings), and rules can do it automatically.
- The tithe is tracked as weekly rows (Sunday–Saturday) with a running balance. Payments apply to the oldest unpaid week first, so one check can cover several weeks or part of one.
- Tithe payments are recognized by rules (payee/memo) and can be marked or unmarked by hand.
- The household owner and the spouse see the personal book. The accountant never does.
- Personal spending gets its own categories, rules, inbox, and a spending summary.

### Success criteria

1. The household owner can open a personal book, add a CSV (or manual) account to it, import statements, and categorize transactions through the existing inbox and rules.
2. The tithe page shows the current balance (behind/ahead), year-to-date owed and paid, and a weekly table that agrees with the transactions under the rules in §3.
3. A rule like "payee contains Grace Church → Tithe" marks tithe checks with no manual work.
4. The accountant (and any user without a personal-book membership) gets 404 on every personal-book URL and sees no personal data in household screens, exports, or the dashboard.
5. Nothing personal leaks into business reports, Schedule C, invoices, mileage, or (later) tax estimates.
6. `demo:seed` produces a personal book that is 1–2 weeks behind on tithe.
7. The PR passes every CI check (Brakeman, bundler-audit, importmap audit, RuboCop, RSpec).

### Out of scope

A configurable tithe rate (it is a constant 10%), tithing on business profit, offerings/giving goals, budgets, savings accounts as a separate concept, Plaid (sub-project 4 feeds this account automatically once it lands), and personal tax effects of giving (itemized deductions remain a non-goal).

## 2. Approach

The personal book is a `Business` row with `kind: "personal"`. Accounts, CSV import, transactions, categories, rules, the inbox, the transaction list, and memberships work unchanged. The work is in (a) the tithe ledger and spending report, and (b) keeping the personal book out of every business-only path through a `business_kind` scope and a `BusinessKindOnly` controller concern. In the UI it is always called "Personal", never a business.

Rejected: a nullable `business_id` with household-scoped accounts, categories, and rules (touches every query and authorization check); separate personal models (duplicates import, rules, and the inbox).

## 3. Data model

```
Business   + kind: business|personal (string, default "business", not null)
           + tithe_start_on (date, nullable; personal only)
           person: required when kind=business, must be nil when kind=personal
           unique: at most one personal row per household (partial unique index on household_id where kind='personal')
Category   schedule_c_line: required and validated against ScheduleC for business categories; must be nil for personal
           + tithable (boolean, not null, default true)  — meaningful on personal income categories
           + tithe    (boolean, not null, default false) — meaningful on personal expense categories
```

Scopes: `Business.business_kind`, `Business.personal`. `Household#personal_book` returns the personal row or nil.

Validations:
- `tithable: false` is only allowed on income categories of a personal book; `tithe: true` only on expense categories of a personal book.
- A personal book cannot be archived.

### 3.1 Creating the personal book

`PersonalBookProvisioner.call(household)` (household owner only, idempotent, mirrors `BusinessProvisioner`):
- creates the `kind: personal` row named "Personal", with no person and no auto-created Cash account;
- copies the personal category template;
- gives the household owner an `owner` membership and the spouse's linked user (if any) an `editor` membership.

When the household owner links a user to the spouse `Person` and a personal book exists, that user gets an `editor` membership on it if they have none.

### 3.2 Personal category template

- Income: Owner draws (tithable), Paychecks & other income (tithable), Refunds & reimbursements (not tithable).
- Expense: Tithe (`tithe: true`), Offerings & giving, Groceries, Dining, Housing, Utilities, Transportation, Insurance, Medical, Kids, Household, Personal, Gifts, Subscriptions, Other.

Users add, rename, and archive personal categories and toggle the two flags, as with business categories.

## 4. Tithe rules

Inputs are the personal book's transactions, across all its accounts, with `transfer = false`, `excluded = false`, and `posted_on >= tithe_start_on`.

- **Tithable income**: `amount_cents > 0` and (category is nil or category `tithable`). Uncategorized deposits count.
- **Tithe paid**: transactions whose category has `tithe: true`, contributing `-amount_cents` (so a check of −$100 pays $100, and a refunded tithe of +$100 un-pays $100). The category's `archived_at` does not matter; its `tithe` flag does.
- **Weeks** run Sunday through Saturday by `posted_on`. The first week starts on the Sunday on or before `tithe_start_on` but counts only transactions on or after it.
- **Owed per week** = `Money.round_rational(Rational(income_cents, 10))`, rounded once per week.
- **Allocation (FIFO)**: walk weeks oldest first; paid cents (net of tithe refunds, summed over the whole range) settle each week's owed amount in order. Each week reports `paid_toward_cents` and a status: `paid` (fully covered), `partial`, or `open`. Weeks with zero owed are `paid`. Any paid total beyond everything owed is **credit**.
- **Running balance** per week = cumulative owed − cumulative paid (by the end of that week, using the actual payment dates, not the FIFO allocation). Positive = behind, negative = ahead.
- **Range**: from the first week through the week containing today. Every week in range is listed, including weeks with no activity, so the balance is continuous.
- If `tithe_start_on` is blank, nothing is computed and the page prompts the owner to set it.

Nothing is stored: the ledger is recomputed on every request, so recategorizing, transferring, or excluding a transaction can never leave stale numbers.

## 5. Components

### Pure (no database)

- `Tithe::Ledger.call(entries:, start_on:, today:)` where `entries` are `Data` structs `(posted_on, amount_cents, kind: :income|:payment)`. Returns weeks (`starts_on, ends_on, income_cents, owed_cents, paid_cents, paid_toward_cents, status, balance_cents`) plus totals (`owed_cents, paid_cents, balance_cents, credit_cents`) and `year_to_date(owed_cents, paid_cents)`.
- `Reports::Spending.call(rows:, months:)` where `rows` are `(month, category_id, amount_cents)`; returns a category × month grid with row and column totals, income and expense sections separated. Expenses display as positive numbers (negated sum), per parent §3.

### Query

- `Tithe::Entries.for(book)` turns transactions into ledger entries, applying the filters in §4. It is the only place that knows the tithe classification SQL.

### Concern

- `BusinessKindOnly` (controllers): `before_action` that raises `ActiveRecord::RecordNotFound` when `@business.personal?`. Included in clients, invoices, invoice payments, invoice PDFs, mileage entries, Schedule C, mileage log, P&L, and aging.
- `PersonalOnly`: the inverse, for the tithe and spending controllers.

## 6. Authorization and exclusions

Personal-book access is plain membership: no membership → 404, viewer reads, editor writes data, owner manages settings (including `tithe_start_on`) and accounts.

Every household-level or cross-business path uses `Business.business_kind`:
- `User#can_view_household?` considers business-kind businesses only (so the accountant keeps household access).
- Household P&L, household transaction export, household invoices, household aging, dashboard receivables, and `InvoiceMatcher.for_businesses`.
- `InvitesController#grantable_businesses`: the personal book is never grantable by invite.
- The businesses list and switcher show business-kind rows; "Personal" gets its own nav entry, visible to its members, and a "Set up personal book" link for the household owner when it does not exist yet.

The household inbox includes a "Personal" group for users who are members of the personal book, through the existing `accessible_businesses` filtering.

Each item in this list gets a spec proving the personal book is excluded.

## 7. Screens and routes

Existing `/businesses/:business_id/...` routes serve the personal book (accounts, CSV imports, transactions, categories, rules, inbox, memberships). The category form shows the "Tithable" checkbox for personal income categories and the "Tithe payment" checkbox for personal expense categories in place of the Schedule C picker.

New:
- `POST /personal_book`: provision (household owner only), then redirect to it.
- `GET /businesses/:business_id/tithe`: summary (balance "Behind $340.00" / "Ahead $50.00" / "Even", year-to-date owed and paid), then weeks newest first with income, owed, paid toward, status, and balance; each row expands (`<details>`) to list its tithable deposits and tithe payments. Owner sees a form for `tithe_start_on` (`PATCH /businesses/:business_id/tithe`). `GET .../tithe.csv` exports the weeks.
- `GET /businesses/:business_id/reports/spending`: month × category grid for a date range (default: current calendar year to date), CSV export.
- Dashboard: a "Tithe" card with the current balance for personal-book members, linking to the tithe page.

## 8. Error handling

- Blank `tithe_start_on`: banner with the form, no numbers.
- `tithe_start_on` in the future: validation error.
- Provisioning twice: returns the existing book.
- Non-owner provisioning: 404 (consistent with household-owner-only screens).
- Flag validations (§3) surface as normal form errors.

## 9. Parent spec amendments

In `2026-10-05-goodbooks-design.md`:
- §1 constraints: "Each bank or card account belongs to exactly one business; there are no mixed personal/business accounts" becomes "Each bank or card account belongs to exactly one book: a business, or the household's single personal book. No account mixes personal and business activity."
- §1 non-goals: "non-business income" is clarified to mean non-business income for tax purposes; the personal book tracks personal cash flow and tithe only.
- §4 decomposition: insert "Personal book + tithing" after Invoices.

## 10. Demo seed

`demo:seed` adds a personal book with:
- one CSV "Joint Checking" account and about 12 months of transactions: weekly owner-draw deposits from each business, occasional refunds (not tithable), groceries, utilities, dining, one move from savings marked as a transfer, and "Grace Church" check payments about twice a month that leave the household 1–2 weeks behind;
- a rule "payee contains Grace Church → Tithe";
- `tithe_start_on` set to the first Sunday 12 months ago;
- the owner as `owner` and the spouse user as `editor`; the accountant has no membership.

## 11. Testing

- `Tithe::Ledger`: exhaustive unit specs: Sunday boundaries (Saturday vs. Sunday transactions), the first partial week, rounding once per week (e.g. three $3.33 deposits), FIFO across several weeks, partial payment, overpayment credit, tithe refund, empty weeks in range, `today` mid-week.
- `Tithe::Entries`: non-tithable category, uncategorized deposit, transfer, excluded, before start date, tithe-category refund, transactions across two accounts in the book, and transactions in business books ignored.
- `Reports::Spending`: grid totals and sign handling.
- Models: `Business` kind/person/uniqueness validations; `Category` flag and `schedule_c_line` rules per kind.
- Request specs for tithe, spending, and personal-book provisioning: non-member 404 (accountant), viewer read-only, editor, owner; `BusinessKindOnly` routes 404 on the personal book.
- Exclusion specs: one per item in §6.
- System spec: import a CSV into the personal account, the Grace Church rule categorizes the check as Tithe, and the tithe page shows the expected balance.
