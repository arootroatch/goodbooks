# goodbooks Sales Tax (Sub-project 4) — Design Spec

Date: 2026-10-08
Status: Draft for review
Kaneo: GB-4
Parent spec: `2026-10-05-goodbooks-design.md` §7 (this document refines and supersedes it). The parent's cross-cutting rules (§3: money, sign convention, authorization, seeds, testing) apply unchanged. Builds on Invoices (`2026-10-06-goodbooks-invoices-design.md`) and Personal book (`2026-10-06-goodbooks-tithing-design.md`).

## 1. Purpose

Track the Tennessee sales tax one business collects, keep it out of income, and answer "what do we owe for this period, when is it due, and is it paid?" Also record the card processor's fees on deposits, so gross sales and the fee expense are both right.

The app records sales tax; it does not compute it per item or act as a point of sale. Collected tax is a liability, not income. Remittances are not expenses ("exclude from both").

### Understanding from the owner

- Sales reach the bank two ways: **Stripe payouts** (one deposit per payout, net of Stripe's fees, often batching several sales) and **invoices** paid by check, ACH, or card through Stripe.
- Some of the business's income is **not taxable** (exempt services), and the TN return lists it as a deduction from gross sales. Some income is not a sale at all (interest).
- Stripe's fees are read from the Stripe payout report and entered on the deposit, so gross sales are pre-fee and the fee is a deductible expense.
- No marketplace (facilitator-remitted) sales and no out-of-state sales.

### Success criteria

1. The owner turns on a sales tax profile for a business and splits income into taxable, exempt, and not-a-sale categories.
2. A Stripe payout can carry its fee and its sales tax, entered from the payout report or computed tax-inclusive at the default rate in one click.
3. Linking an invoice that carries sales tax to a deposit (including a batched, fee-reduced Stripe payout) puts the right share of that tax on the deposit, and unlinking takes exactly that share back off.
4. Each filing period shows gross, exempt, and taxable sales, tax collected, remitted, and balance owed, with a status (open, due, overdue, filed, paid) that can never go stale.
5. P&L, Schedule C, household P&L, and (later) the tax engine count income net of collected sales tax and gross of processor fees, with fees as an expense and remittances in neither.
6. The dashboard shows each sales-tax business's next due date and open balance, and warns when a period is overdue.
7. The personal book never shows any of it.
8. `demo:seed` shows a business with filed, paid, and due periods, Stripe payouts with fees and tax, and a taxed invoice paid through a batched payout.
9. The PR passes every CI check (Brakeman, bundler-audit, importmap audit, RuboCop, RSpec).

### Out of scope

Marketplace and out-of-state sales (and the parent's `sales_channel` and `destination_state`), local rate tables, the single-article cap and per-item exemption logic (tax stays editable), filing with the TN Department of Revenue, penalties and interest, other states, and processor fees on the personal book.

## 2. Approach

Taxability lives on the **category**, not the transaction: income categories carry a sales tax treatment, so the existing rules and inbox pick the treatment when they pick the category, and rules need no change. Transactions gain only two amounts: direct sales tax and processor fee. An invoice's tax share lives on the `InvoicePayment` that links it, so a payout that mixes invoiced and direct sales keeps the two apart and nothing is ever incremented in place.

Periods are **derived** from the profile by a pure calendar; only the act of filing is stored. Every figure and status is recomputed on each request, as the tithe ledger is.

Rejected: a `sales_channel` enum per transaction (the parent's design; adds an inbox control and a rule-schema change for a distinction the category already makes); incrementing `transactions.sales_tax_cents` from invoice links (mixes invoiced and hand-entered tax in one column, so a later edit clobbers one with the other); stored `SalesTaxPeriod` rows with a stored `paid` status (goes stale when a deposit is recategorized).

## 3. Data model

```
SalesTaxProfile  business (unique), tn_account_number (nullable), filing_frequency: monthly|quarterly|annual,
                 default_rate_bps (integer, 1..2000; e.g. 925 = 7% state + 2.25% local),
                 starts_on (date: the first day the business collected TN tax), active (boolean)
SalesTaxFiling   business, period_starts_on (date), filed_on (date), confirmation_number (nullable)
                 unique(business, period_starts_on)
Category         + sales_tax_treatment: taxable|exempt|not_a_sale (string, nullable; income categories of
                   business-kind books only, nil otherwise)
                 + processor_fees (boolean, not null, default false; at most one per business, expense only)
                 kind gains a third value: sales_tax_remittance (schedule_c_line must be nil)
Transaction      + sales_tax_cents (integer, not null, default 0)       — direct tax only (§4.1)
                 + processor_fee_cents (integer, not null, default 0)
                 + sales_tax_period_starts_on (date, nullable)          — remittances only (§5.2)
Invoice          + sales_tax_cents (integer, not null, default 0; part of amount_cents)
InvoicePayment   + sales_tax_cents (integer, not null, default 0)       — this payment's pro-rated share
```

`SalesTaxProfile` and `SalesTaxFiling` belong only to business-kind books (validation). `Business has_one :sales_tax_profile`; `Business#collects_sales_tax?` = profile present and active.

### 3.1 Derived values (never stored)

- A deposit's **gross** = `amount_cents + processor_fee_cents`.
- A deposit's **invoice tax** = sum of its invoice payments' `sales_tax_cents`.
- A deposit's **total tax** = `sales_tax_cents + invoice tax`.
- A deposit's **net income** = gross − total tax. This is what reports count as income.
- `allocated_cents` (Invoices) is unchanged; **`unallocated_cents` = gross − allocated** (was `amount_cents − allocated`).

### 3.2 Category treatment defaults

- A new income category in a business-kind book gets `taxable` if `schedule_c_line == "1"`, else `not_a_sale`. Expense, remittance, and personal categories get nil.
- The migration backfills existing income categories the same way.
- The treatment field is shown and editable only when the business collects sales tax; without a profile it still exists (and defaults sensibly) but has no visible effect.

### 3.3 Categories created for the work

- **Merchant fees** (expense, line 10, `processor_fees: true`) joins the default business template (`CategoryTemplate::CATEGORIES`). A data migration adds it to every existing business-kind book; if a category named "Merchant fees" already exists there, that row is flagged instead. It can be renamed or archived; reports find it by the flag.
- **Sales tax remittance** (kind `sales_tax_remittance`, no Schedule C line) is created when a profile is first activated, if the business has none. Only one active remittance category per business.

## 4. Recording sales tax and fees

### 4.1 Field rules

Processor fee, on any business-kind book (with or without a profile):
- `processor_fee_cents >= 0`.
- A fee > 0 requires `amount_cents > 0`, `transfer = false`, `excluded = false`, and a category that is nil or income.

Direct sales tax, only when the business collects sales tax:
- `sales_tax_cents >= 0`.
- A value > 0 requires `amount_cents > 0`, `transfer = false`, `excluded = false`, and a `taxable` income category.

Both:
- **total tax < gross**.
- On the personal book both must be 0.

Guards (same style as the linked-deposit guard, one message per case):
- A transaction with a fee > 0 cannot be made a transfer, excluded, or moved to a non-income category or nil: "Clear the processor fee first."
- A transaction with total tax > 0 cannot be made a transfer, excluded, or moved to anything but a `taxable` income category: "Clear the sales tax first." (Invoice tax is cleared by unlinking, which the existing linked-deposit guard already requires.)
- A category's treatment cannot move away from `taxable` while any of its transactions carry total tax > 0; its kind cannot change while any carry a fee > 0.
- A category's kind cannot change to or from `sales_tax_remittance` while it has transactions: "can't change to or from a remittance category while it has transactions".
- A profile cannot be deleted, only deactivated. Deactivating hides the sales tax screens and fields but keeps every number; reactivating restores them.
- `RuleApplier` is unaffected: it only touches inbox rows, which have no category and so, by the rules above, no direct tax.

### 4.2 Stripe payouts (direct)

- The transaction form shows **Processor fee** for positive transactions in business-kind books, and **Sales tax** (plus **Tax-inclusive at default rate**) when the business collects sales tax and the selected category is taxable.
- **Tax-inclusive at default rate** sets `sales_tax_cents` = `SalesTax::InclusiveTax.call(gross_cents: gross − allocated, rate_bps: default_rate_bps)` = `Money.round_rational(Rational(base × rate_bps, 10_000 + rate_bps))`. The base is the **unallocated** gross, so invoice-paid portions (which already carry their own tax) are never taxed twice. A Stimulus controller computes the same value client-side for instant feedback; the server recomputes on save when the button is used (`apply_inclusive_tax=1`), so the client value is never trusted.
- Inbox rows are uncategorized, so they can carry neither tax nor a taxable category; the inbox gains no tax controls. Tax and fees are entered on the transaction form after categorization. The transaction list gets a "Sales tax" filter: taxable deposits with no tax and no invoice links ("needs tax"), to find payouts that still need entering.

### 4.3 Invoiced sales

- The invoice form gains **Sales tax** (≥ 0, < amount, shown when the business collects sales tax). It is part of `amount_cents`. With payments linked, neither the amount nor the sales tax of a taxed invoice can change: "Unlink payments before changing the amount or sales tax."
- `InvoicePayments.link` computes the payment's share = `Money.round_rational(Rational(payment_cents × invoice.sales_tax_cents, invoice.amount_cents))`, rounded once per payment, and stores it on the new `InvoicePayment`. The deposit's own `sales_tax_cents` is never touched. When the payment completes the invoice, the share is adjusted to `invoice.sales_tax_cents − sum of earlier shares` so an invoice's shares always sum to its tax exactly.
- An invoice with tax > 0 can only be linked to a deposit whose category is nil or `taxable`: "This invoice includes sales tax — categorize the deposit as a taxable sale." When the deposit is uncategorized, the default category is the business's single active `taxable` line-1 category (falling back to the existing gross-receipts picker when there are several).
- `unlink` destroys the payment, and with it the share. Nothing else to reverse.
- **Fees on the Record payment page**: each candidate row gains an optional **Processor fee** field. Linking with a fee sets the deposit's `processor_fee_cents` (only if it is 0; otherwise the field is shown read-only) in the same DB transaction, under the same locks, before allocation. A $970.70 payout with a $29.30 fee then pays a $1,000.00 invoice in full.
- Exact-match logic (`InvoiceMatcher`, Record payment's exact section) uses unallocated **gross**, so a payout whose fee is already entered matches its invoice exactly.

### 4.4 Remittances

- A remittance is a transaction in the `sales_tax_remittance` category (usually a negative ACH to the TN DOR; a positive refund of an overpayment is allowed). Rules can categorize into it.
- When a transaction enters the remittance category with `sales_tax_period_starts_on` nil, a `before_save` sets it to `SalesTax::RemittancePeriod.default_for(business, posted_on)`: the oldest ended period (ends_on < posted_on) with a balance owed > 0, else the most recent ended period, else the current one.
- The value must be the start of a period in the profile's calendar (validation). Leaving the category clears it. A remittance dated before the profile's `starts_on` has no period and is rejected: "is before the first sales tax period" (on `sales_tax_period_starts_on`).
- The transaction form and the period page let an editor change the period from a select of the calendar's periods.

## 5. Periods

### 5.1 Calendar (`SalesTax::Calendar`, pure)

`SalesTax::Calendar.new(starts_on:, frequency:, today:)` returns `Period` structs `(starts_on, ends_on, due_on)`:
- Monthly periods are calendar months, quarterly are calendar quarters, annual are calendar years.
- The first period is the one containing the profile's `starts_on`; the last is the one containing `today`.
- `due_on` = the 20th of the month after `ends_on`, rolled forward past Saturdays, Sundays, and TN state holidays until a business day.
- `period_for(date)` and `include_start?(date)` support remittance assignment and validation.

`SalesTax::Holidays.for(year)` computes, for any year, the only TN state holidays that can delay a return due on the 20th: MLK Day (3rd Monday of January, Jan 15–21), Presidents' Day (3rd Monday of February, Feb 15–21), and Good Friday (two days before Easter, Mar 20–Apr 23). Every other TN state holiday is a fixed date other than the 20th or falls nowhere near it, and no holiday can fall on the Monday after a weekend 20th (the 21st or 22nd) except MLK Day and Presidents' Day, which the rule already covers. No holiday list is maintained, so no year can be missing.

### 5.2 Period report (`SalesTax::PeriodReport`, pure)

Inputs: the period, `deposits` (structs: posted_on, treatment, gross_cents, total_tax_cents), `remittances` (structs: posted_on, amount_cents), the filing (or nil), and today. Deposits are those with a taxable or exempt category, `transfer = false`, `excluded = false`, `posted_on` in the period (cash basis). Remittances are those whose `sales_tax_period_starts_on` is the period's start.

| Figure | Definition |
|---|---|
| Gross sales | sum of gross, taxable + exempt deposits (tax included) |
| Exempt sales | sum of gross, exempt deposits |
| Taxable sales | sum of (gross − total tax), taxable deposits |
| Tax collected | sum of total tax |
| Remitted | −sum of remittance amounts |
| Balance owed | collected − remitted (negative = overpaid) |

Status, first match wins:

| Status | Condition |
|---|---|
| paid | filed and balance ≤ 0 |
| filed | filed and balance > 0 |
| overdue | not filed and today > due_on |
| due | not filed and today > ends_on |
| open | otherwise |

### 5.3 Query

`SalesTax::Entries.for(business, range)` loads the deposit and remittance structs above in two queries. It is the only place that knows the sales tax SQL (gross, invoice-tax subquery, treatment join).

## 6. Reports

`Reports::CategoryTotals.load` is the single source for P&L, Schedule C, household P&L, and the transaction export's totals. It changes so that:

- Income categories sum **net income** (§3.1): `amount_cents + processor_fee_cents − sales_tax_cents − invoice tax`.
- Expense categories sum `amount_cents` as today.
- The business's `processor_fees` category gets an extra negative total equal to −sum of `processor_fee_cents` on countable categorized transactions in range, merged with any real transactions in that category (so the expense shows as positive in reports).
- `sales_tax_remittance` totals are dropped (neither income nor expense). `ProfitAndLoss` already selects only `income`/`expense` kinds; a spec pins that.

The transaction export gains `processor_fee`, `sales_tax` (total), and `net_income` columns.

Specs prove, for one business: a $1,000 taxable Stripe payout netting $970.70 with $82.41 tax shows $917.59 income and $29.30 Merchant fees; an invoice-linked deposit's share is netted; a remittance appears in neither; Schedule C line 1 and line 10 agree; and the household P&L matches the sum of its businesses.

## 7. Screens and routes

```ruby
resources :businesses do
  resource :sales_tax_profile, only: %i[show update], path: "sales_tax"     # show = period list + profile form
  resources :sales_tax_periods, only: :show, param: :starts_on, path: "sales_tax/periods" do
    resource :filing, only: %i[create destroy], controller: "sales_tax_filings"
  end
end
```

- **Sales tax page** (`/businesses/:id/sales_tax`): for owners, the profile form (TN account number, frequency, default rate as a percent with up to two decimals, start date, active). Below it, the periods newest first: period, due date, collected, remitted, balance, status badge. Without a profile, viewers and editors see "Sales tax isn't set up for this business"; owners see the form.
- **Period page** (`.../sales_tax/periods/2026-07-01`): the §5.2 figures, then its taxable and exempt deposits (date, account, payee, gross, fee, direct tax, invoice tax) and its remittances. Editors see **Mark filed** (filed_on default today, confirmation number) or, once filed, the filing details and **Unfile**. CSV export (`.csv`) via `Reports::CsvSafe`. A `starts_on` that is not a period start in the calendar → 404.
- **Category form**: "Sales tax treatment" select on income categories when the business collects sales tax; the remittance kind is offered in the kind select only then.
- **Transaction form**: fee and tax fields per §4.2; remittances get the period select.
- **Invoice form**: sales tax field per §4.3. Invoice show page shows the tax and each payment's share.
- **Record payment**: the fee field per §4.3.
- **Dashboard**: a card per business that collects sales tax: "Sales tax · next due Oct 20 · owed $1,234.56" (sum of balance owed over periods not paid). An overdue period shows a banner on the dashboard and on the business page linking to it.
- **Navigation**: the business nav gains "Sales tax" for business-kind books (owners always, to set it up; others only when a profile exists).

### 7.1 Authorization

Every new controller includes `BusinessScoped` then `BusinessKindOnly`. Viewers read pages and CSV; editors file, unfile, and enter tax and fees; owners create and update the profile. Strong params never permit `*_id` keys; the period is resolved from `params[:starts_on]` through the calendar.

## 8. Error handling

- Every validation failure is a form error or flash with a specific message (§4.1); nothing fails silently or 500s.
- A remittance whose period start is not in the calendar: validation error on the transaction.
- A period cannot be filed before it ends: "can't be filed before the period ends" (`filed_on` must be after the period's `ends_on`).
- Deactivating the profile: screens hidden, data kept, remittance category left as is.
- Profile `starts_on` in the future or a rate outside 0.01%–20%: validation errors.
- Changing `filing_frequency` or `starts_on` after filings or remittances exist would orphan them: blocked with "Filings or remittances exist for the current periods."

## 9. Components summary

| Unit | Kind | Responsibility |
|---|---|---|
| `SalesTax::Calendar` | pure | periods and due dates |
| `SalesTax::Holidays` | pure | the TN holidays that can delay a 20th, computed by rule |
| `SalesTax::InclusiveTax` | pure | gross × r / (1 + r), rounded once |
| `SalesTax::PeriodReport` | pure | §5.2 figures and status |
| `SalesTax::RemittancePeriod` | query | default period for a new remittance |
| `SalesTax::Entries` | query | deposit and remittance structs for a range |
| `SalesTaxProfile`, `SalesTaxFiling` | models | profile and filings |
| `SalesTaxProfile#activate!` | model method | creates the remittance category on first activation |
| `Reports::CategoryTotals` | query (changed) | net income, synthetic fee totals, remittances dropped |
| `Invoices::Allocation`, `InvoiceMatcher`, `InvoicePayments` | changed | gross-based allocation, tax shares, fee on link |

## 10. Testing

TDD throughout; clean output.

- **Pure specs (no DB)**: `Calendar` (each frequency, `starts_on` mid-period, year boundary, 20th on a weekday / Saturday / Sunday / holiday / holiday-then-weekend, `period_for`); `Holidays` (MLK, Presidents' Day, and Good Friday for several years, including a Good Friday on April 20, 2057); `InclusiveTax` (9.25% on $1,000.00 → $84.67, rounding half-up boundary, zero base); `PeriodReport` (every figure, each status, overpayment, empty period); `Invoices::Allocation` (gross inputs).
- **Model specs**: every §4.1 rule and guard; category treatment defaults and backfill; one `processor_fees` category per business; remittance kind has no Schedule C line; profile and filing only on business-kind books; frequency change blocked once filings exist; remittance period default and validation.
- **Service specs** (`InvoicePayments`): share computed and stored; final payment's share absorbs rounding; batched payout (invoice share + direct tax) keeps both; unlink removes only the share; fee entered during link makes an exact match; tax invoice rejected for an exempt deposit; taxable default category.
- **Query specs**: `SalesTax::Entries` (treatment, transfers, excluded, period bounds, invoice-tax subquery), `RemittancePeriod`, and `Reports::CategoryTotals` per §6.
- **Request specs**: standard matrix (non-member 404, viewer read-only, editor files and enters amounts but cannot edit the profile, owner does everything) for profile, period, filing, CSV; personal book → 404 on every sales tax route; a bad `starts_on` → 404; dashboard card and overdue banner; CSV neutralizes formula prefixes.
- **System spec**: enter a fee on a Stripe payout, click tax-inclusive, record a remittance, mark the period filed, and see it paid.
- **Demo seed spec**: the seeded business's periods show filed + paid, and the current one due.

## 11. Demo seed

`demo:seed` gives the owner's business an active quarterly profile (default rate 9.25%, `starts_on` five quarters ago) and:
- splits income into "Sales" (taxable) and a new "Consulting" (exempt) category, with a rule "payee contains STRIPE → Sales";
- weekly Stripe payouts with fees (2.9% + $0.30 per sale, summed) and tax entered; a few left without tax so the "needs tax" filter has rows;
- three invoices with sales tax: one paid by check, one paid inside a batched Stripe payout alongside direct sales, one open;
- exempt consulting deposits;
- every completed quarter except the latest is filed, with a remittance equal to its collected tax (status paid); the latest completed quarter is unfiled (due or overdue, depending on today).

## 12. Parent spec amendments

In `2026-10-05-goodbooks-design.md`:
- §1 non-goals: add "marketplace and out-of-state sales tracking".
- §7: replace with a pointer to this spec and a one-paragraph summary.
- §9.2 step 1: "income (net of collected sales tax, §7)" becomes "income (net of collected sales tax and gross of processor fees, with processor fees as an expense; see the sales tax spec §6)".

In `2026-10-06-goodbooks-invoices-design.md`: §2 derived values and §3.1–3.2 read "unallocated" as gross-based (this spec §3.1); add a pointer.

In `docs/roadmap.md`: sub-project 4's Design and Documents rows point here; status moves per the convention.
