# goodbooks Tax Engine (Sub-project 6) — Design Spec

Date: 2026-10-12
Status: Draft for review
Kaneo: GB-6
Parent spec: `2026-10-05-goodbooks-design.md` §9 (this document refines and supersedes it). The parent's cross-cutting rules (§3: money, sign convention, authorization, seeds, testing) apply unchanged. Builds on Sales tax (`2026-10-08-goodbooks-sales-tax-design.md`, income net of collected tax) and Personal book (`2026-10-06-goodbooks-tithing-design.md`, kept out of every estimate).

## 1. Purpose

Tell the household how much federal estimated tax to pay each quarter, when it is due, and why, for a married-filing-jointly return with two sole proprietors on Schedule C and no other income. Show both the regular and the annualized (Form 2210 Schedule AI) installment, pay the lesser, and keep a log of what was actually paid.

### Understanding from the owner

- Every §9 input applies: home office, self-employed health insurance, retirement contributions (SEP or Solo 401(k)), and prior-year total tax and AGI for safe harbor.
- Income is uneven enough that the annualized method matters, so both methods stay.
- Estimated payments are made online (IRS Direct Pay / EFTPS) and show up as debits in the joint checking account in the personal book. A payment is recorded by linking that debit. Manual entry stays for payments with no transaction (an overpayment applied from last year's return).
- The taxes page links to the IRS online payment site in a new tab. The URL may change, so it is editable in a household settings page.
- The household owner edits every tax input. A business's owner also edits that business's home office, and a person's own user edits that person's adjustments.

### Success criteria

1. The household owner enters prior-year total tax and AGI, and the 2026 parameters come seeded and verified against IRS sources.
2. The taxes page shows, for the current quarter, the regular installment, the annualized installment, and "pay at least" (the lesser, floored at 0), with the due date rolled past weekends and holidays.
3. A line-by-line worksheet shows every intermediate number: per-business profit, home office used and carried over, per-person SE tax, Additional Medicare, AGI, QBI, taxable income, tax by bracket, total, safe harbor, required annual payment.
4. Recording a payment by picking the IRS debit takes one form, and the payment reduces what is shown as due.
5. Home office (simplified or regular) per business and year fills Schedule C line 30 and reduces profit in the estimate, capped so it never creates a loss.
6. Self-employed health insurance and retirement contributions per person reduce AGI and QBI, with the health insurance cap applied and a warning when a contribution exceeds the year's limit.
7. The page never guesses: missing parameters or prior-year figures produce a banner linking to the form that fixes them.
8. The personal book never feeds an estimate, and the accountant (who has household access but no personal-book membership) sees payment dates and amounts but never a personal-book transaction.
9. A "Pay on IRS.gov" link opens the household's configured URL in a new tab, from the taxes page and the dashboard card.
10. `demo:seed` shows the current tax year with prior-year figures, a home office, adjustments for both people, every installment already due paid through linked debits, and the next one due.
11. The PR passes every CI check (Brakeman, bundler-audit, importmap audit, RuboCop, RSpec).

### Out of scope

State taxes; filing statuses other than MFJ; W-2, investment, or any non-Schedule C income; credits; itemized deductions; AMT; the full QBI computation above the threshold (W-2 wage and UBIA limits, SSTB phase-out) and the OBBBA $400 minimum QBI deduction; the deductions added by the 2025 tax law for tips, overtime, seniors, and car loan interest; penalty computation; Form 2210's recapture rules between methods; computing a maximum retirement contribution; storing past recommendations; reminders or notifications.

## 2. Approach

A pure engine computed on every request. `Tax::Inputs` loads plain structs; `Tax::Estimator` takes them and returns a `Tax::Estimate` holding every worksheet line. Nothing derived is stored, so the estimate can never go stale when a transaction is recategorized. This is the pattern of `SalesTax::PeriodReport` and the report calculators.

Net profit comes from the existing report code (`Reports::CategoryTotals`, `Reports::MileageTotals`, `Reports::ScheduleCSummary`), so it is already net of collected sales tax, gross of processor fees, with `deductible_bps` and mileage applied, and limited to business-kind books.

Rejected: storing a snapshot of each quarter's recommendation (goes stale on recategorization; the payment log already records what was paid), and a data-driven form-line engine modeling 1040/SE/2210 lines (machinery for one filing status and one entity type).

## 3. Data model

```
TaxParameters    (existing table, one row per year; new columns, all nullable)
                 standard_deduction_mfj_cents, brackets_mfj (json: [{"floor_cents", "rate_bps"}] ascending, first floor 0),
                 ss_wage_base_cents, se_earnings_bps, ss_rate_bps, medicare_rate_bps,
                 additional_medicare_bps, additional_medicare_threshold_mfj_cents,
                 qbi_bps, qbi_threshold_mfj_cents,
                 home_office_simplified_rate_cents, home_office_simplified_max_sqft,
                 safe_harbor_high_agi_threshold_cents,
                 annual_additions_limit_cents, elective_deferral_limit_cents
Household        + irs_payment_url (string, not null, default "https://www.irs.gov/payments/direct-pay")
TaxYear          household, year                            unique(household, year)
                 prior_year_total_tax_cents, prior_year_agi_cents   (both nullable)
EstimatedPayment tax_year, quarter (1–4), paid_on, amount_cents (> 0),
                 debit (nullable, a Transaction)            unique(debit_id) where not null
HomeOffice       business, year                             unique(business, year)
                 calculation: simplified|regular, office_sqft, home_sqft (regular only),
                 rent_cents, mortgage_interest_cents, utilities_cents, insurance_cents,
                 repairs_cents, other_cents, depreciation_cents   (all default 0)
PersonAdjustment person, year                               unique(person, year)
                 se_health_insurance_cents, retirement_contribution_cents (both default 0),
                 retirement_plan: sep|solo_401k (required when a contribution is entered)
```

### 3.1 Rules

- **`TaxParameters#estimate_ready?`** is true when every new column is present and `brackets_mfj` is a non-empty, ascending list starting at floor 0. The existing mileage rate stays required as before. The form validates the bracket rows (non-negative floors, strictly ascending, rate 0–10000 bps).
- **`TaxYear`** rows are created on demand: the first save of the prior-year form, or the first payment recorded for that year (`TaxYear.for(household, year)` = find or create).
- **`EstimatedPayment`** (the link is named `debit`, column `debit_id`, like `InvoicePayment#deposit`; nothing is named `transaction`):
  - Linked: the transaction must be negative and belong to an account the recording user can access; the amount defaults to its absolute value and `paid_on` to its date. Both stay editable (an IRS debit can include a separate balance-due payment).
  - The quarter defaults to the first installment of the tax year whose due date is on or after `paid_on`, else 4. Editable.
  - Destroying a linked transaction nullifies the link (`Transaction has_one :estimated_payment, foreign_key: :debit_id, dependent: :nullify`, and the foreign key is `on_delete: :nullify`); the payment stays as a manual one.
- **`HomeOffice`** belongs only to business-kind books (validation). `home_sqft` is required and ≥ `office_sqft` for the regular method. (The column is `calculation`, not `method`, which would shadow `Object#method`.) `depreciation_cents` is the business portion, entered from the accountant.
- **`PersonAdjustment`** amounts are full-year expected figures.

## 4. Calculation (`Tax::Estimator`, pure)

### 4.1 Inputs (`Tax::Inputs.load(household:, year:, tax_parameters:, today:)`, query)

For each business-kind business (archived ones included), and for each Schedule AI period, the year-to-date **profit before home office** = `Reports::ScheduleCSummary#net_profit_cents` over Jan 1 to the period's end. Also: the business's person, the year's `TaxParameters`, the `TaxYear`, each person's `PersonAdjustment`, each business's `HomeOffice`, and the payments. Archived businesses are included because their profit for the year is still taxable.

Schedule AI periods: Q1 Jan–Mar (factor 4), Q2 Jan–May (2.4), Q3 Jan–Aug (1.5), Q4 Jan–Dec (1).

**A period still in progress** (its end is after `today`) uses data through `today`, annualized by days in the year ÷ days elapsed, and the worksheet labels it "projected from N days". A period that has ended uses its standard factor. Factors are `Rational`.

### 4.2 Per period

All amounts annualized per §4.1 where they come from business profit; full-year inputs (home office, health insurance, retirement) are applied after annualizing, not multiplied. This approximates Schedule AI and the worksheet says so. Every line is rounded once with `Money.round_rational`; the rounded value is the one used downstream.

1. **Business profit** = annualized profit before home office.
2. **Home office**: simplified = min(office_sqft, max_sqft) × rate; regular = office_sqft / home_sqft × (rent + mortgage interest + utilities + insurance + repairs + other) + depreciation. Used = min(that, max(0, business profit)); carryover = the rest (informational). Net profit = business profit − used.
3. **SE tax per person**: SE earnings = max(0, sum of the person's net profits) × se_earnings_bps. Below $400, SE earnings and SE tax are 0. SS = ss_rate × min(SE earnings, wage base); Medicare = medicare_rate × SE earnings. A loss in one business offsets the same person's other businesses.
4. **Additional Medicare** (household) = additional_medicare_bps × max(0, total SE earnings − threshold). Not part of the ½ SE tax deduction.
5. **Adjustments per person**: half SE tax = ½ (SS + Medicare). Retirement = the entered contribution. SE health insurance = min(entered premiums, max(0, person's net profit − half SE tax − retirement)).
6. **AGI** = total net profit − Σ half SE tax − Σ SE health insurance − Σ retirement. May be negative.
7. **Taxable before QBI** = max(0, AGI − standard deduction).
8. **QBI** = max(0, total net profit − Σ half SE tax − Σ SE health insurance − Σ retirement). Deduction = qbi_bps × min(QBI, taxable before QBI). Warning when taxable before QBI > the QBI threshold.
9. **Taxable income** = taxable before QBI − QBI deduction. **Income tax** = brackets applied progressively; the worksheet shows each bracket's slice.
10. **Total projected tax** = income tax + Σ SE tax + Additional Medicare.

### 4.3 Installments

The page shows one **selected quarter** (default: the earliest installment whose due date is on or after today; past the Q4 due date, Q4). Paid through quarter k = Σ payments with quarter ≤ k.

- **Safe harbor** = prior-year total tax × (110% if prior-year AGI > the high-AGI threshold, else 100%). Omitted (with a banner) when either prior-year figure is missing. A prior-year tax of 0 gives a safe harbor of 0.
- **Required annual** = min(90% × total projected tax of the selected quarter's period, safe harbor).
- **Regular installment k** = max(0, required annual × k/4 − paid through k).
- **Annualized installment k** = max(0, total projected tax of period k × applicable percentage (22.5, 45, 67.5, 90%) − paid through k). Shown for k ≤ the selected quarter; later quarters show "—".
- **Pay at least k** = the lesser of the two (the regular one alone where annualized is "—"). Labeled an approximation of Form 2210.

### 4.4 Warnings (on the `Tax::Estimate`)

QBI above threshold; prior-year figures missing; a retirement contribution over the limit (SEP: min(annual additions limit, 20% × (person's net profit − half SE tax)); Solo 401(k): min(annual additions limit, elective deferral limit + 20% × (person's net profit − half SE tax))); the full-year home office exceeds profit (carryover). The taxes page also shows the count of uncategorized transactions in business-kind books for the year, linking to the household inbox (computed by the controller, not the engine).

### 4.5 Due dates (`Tax::DueDates`, pure)

Apr 15, Jun 15, Sep 15 of the year and Jan 15 of the next, each rolled forward one day at a time while it falls on a weekend or holiday. Only two federal or DC holidays can land on a roll date, both computed (no per-year list):
- Martin Luther King Jr. Day (third Monday of January: Jan 15–21).
- DC Emancipation Day, Apr 16, observed on Friday Apr 15 when Apr 16 is a Saturday and Monday Apr 17 when it is a Sunday.

Known cases: 2017 → Apr 18, 2022 → Apr 18, 2023 → Apr 18.

## 5. Schedule C line 30

`Reports::ScheduleCSummary` takes an optional `home_office_cents:`. The Schedule C report passes the business's full-year home office (§4.2 step 2 formula, no annualization) capped at that year's actual profit before home office, and shows line 30 with it. With no `HomeOffice` row, line 30 shows "—" and an "Add home office" link for users allowed to edit it. The P&L report is unchanged.

## 6. Screens and routes

| Route | Who | What |
|---|---|---|
| `GET /taxes` | household access | redirect to the current year |
| `GET /taxes/:year` | household access | the taxes page; `?quarter=1..4` selects a quarter |
| `GET/PATCH /taxes/:year/edit` | household owner | prior-year total tax and AGI (creates the `TaxYear`) |
| `/taxes/:year/payments` `new create edit update destroy` | household owner | estimated payments |
| `/businesses/:business_id/home_offices/:year` `edit update` | household owner or business owner | home office for a business-kind book |
| `/people/:person_id/adjustments/:year` `edit update` | household owner or the person's user | health insurance and retirement |
| `/tax_parameters` (existing) | household owner | grows the new fields; brackets edited as rows: the existing brackets plus two blank rows; blank rows are dropped on save (no JavaScript) |
| `GET/PATCH /household/edit` | household owner | household name and IRS payment URL |

`edit`/`update` on home offices and adjustments create the row on first save (find or initialize by year).

**Taxes page** (a household page, "Taxes" in the household nav for users with household access):
- Due card: "Pay at least **$X** by **Jun 15, 2026**" and a **Pay on IRS.gov ↗** link (`target="_blank" rel="noopener noreferrer"`) to `Household#irs_payment_url`.
- Quarter switcher; installment table (due date, regular, annualized, paid, pay at least) for all four quarters.
- Per-person SE breakdown; per-business profit, home office used, carryover, with edit links for those allowed.
- Worksheet: a `<details>` element with every §4.2 line for the selected period.
- Payment log: date, quarter, amount, linked transaction (payee and account, shown only when the viewer can access its book), edit and delete for the household owner.
- Banners and warnings (§4.4, §8), each linking to the form that fixes it.
- A permanent note: "This is an estimate. Verify with your accountant."

**Payment form**: a transaction picker listing negative transactions from accounts the user can access, dated Jan 1 of the tax year through Jan 31 of the next year, newest first, with a payee search. Payees matching `IRS|USATAXPYMT|EFTPS` (case-insensitive) sort first. "No transaction" switches to manual date and amount.

**Dashboard**: a "Next estimated tax" card for users with household access: due date, pay at least, and the IRS link. Hidden when parameters for the current year aren't ready.

**Settings nav**: adds "Household" (household owner).

### 6.1 Authorization

- Pages a user can't see return 404: the taxes pages without household access, a home office on a book the user can't access or on the personal book, adjustments for a person in another household.
- Pages a user can see but can't change return 403, as the existing household-owner screens do: payments and the prior-year form for anyone but the household owner, a home office for a non-owner member, adjustments for anyone but the household owner and the person's user.
- A payment's transaction is looked up through `Current.user.accessible_businesses`; an inaccessible id is 404.

## 7. Seeds

`db/seeds.rb` fills the 2026 row (`find_or_create_by!` then `update!` of any blank new column, so an existing row gains the values without overwriting edits). Each value cites its source in a comment and is checked against the source at implementation:

| Field | 2026 | Source |
|---|---|---|
| standard deduction MFJ | $32,200 | Rev. Proc. 2025-32 / IRS news release |
| brackets MFJ | 10% 0; 12% $24,800; 22% $100,800; 24% $211,400; 32% $403,550; 35% $512,450; 37% $768,700 | Rev. Proc. 2025-32 |
| SS wage base | $184,500 | SSA 2026 COLA fact sheet |
| SE earnings / SS / Medicare / Additional Medicare | 92.35% / 12.4% / 2.9% / 0.9% | IRC §§1401, 1402 |
| Additional Medicare threshold MFJ | $250,000 | IRC §1401(b)(2) (not indexed) |
| QBI rate / threshold MFJ | 20% / $403,500 | IRC §199A; Rev. Proc. 2025-32 |
| home office simplified | $5/sq ft, 300 sq ft | Rev. Proc. 2013-13 |
| safe harbor high-AGI threshold | $150,000 | IRC §6654(d)(1)(C) |
| annual additions limit (§415(c)) | $72,000 | IRS 2026 retirement plan COLA notice |
| elective deferral limit (§402(g)) | $24,500 | IRS 2026 retirement plan COLA notice |

## 8. Error handling

- Parameters not ready for the year: the taxes page shows inputs, the payment log, and a banner linking to the parameters form; no estimate numbers. The dashboard card is hidden.
- Prior-year figures missing: the estimate runs without safe harbor; a banner links to the prior-year form.
- Uncategorized transactions in the year: a warning with the count, reusing `shared/_uncategorized_notice`.
- Mileage rate missing for the year: the mileage rate is a required column, so a year without one has no `TaxParameters` row and gets the incomplete-figures banner above.
- A year outside 2000–2100 in the URL: 404.
- Validation errors re-render the form with `shared/_errors` and 422.

## 9. Components summary

**Pure (no database):** `Tax::DueDates` (due dates, and `quarter_on` for a payment's default quarter), `Tax::Brackets` (progressive tax with slices), `Tax::HomeOfficeDeduction`, `Tax::PeriodCalculator` → `Tax::PeriodWorksheet`, `Tax::Estimator` → `Tax::Estimate`, and the input value objects.

**Query:** `Tax::Inputs`, `Tax::PaymentCandidates` (transaction picker scope).

**Models:** `TaxParameters` (extended), `Household` (`irs_payment_url`), `TaxYear`, `EstimatedPayment`, `HomeOffice`, `PersonAdjustment`.

**Controllers:** `TaxYearsController` (show, edit, update), `EstimatedPaymentsController`, `HomeOfficesController`, `PersonAdjustmentsController`, `HouseholdsController` (edit, update), `TaxParametersController` (extended), `ScheduleCsController` (line 30), `DashboardsController` (card).

## 10. Testing

- `Tax::Estimator`: hand-computed worked examples checked into the specs, each with its arithmetic in a comment: zero profit; SE earnings under $400; one spouse above the wage base; both spouses with profit; Additional Medicare threshold crossed; safe harbor at 100% and 110%; each of the four periods' factors; a period in progress (days-elapsed factor); home office capped by profit with carryover; SE health insurance cap; a loss in one business offsetting the same person's other business; QBI threshold warning; missing prior year; payments exceeding the requirement (floored at 0); the lesser-of choice going each way.
- `Tax::DueDates`: weekend rolls, MLK Day on Jan 15–21, Emancipation Day observed (2017, 2022, 2023 → Apr 18).
- `Tax::Brackets`, `Tax::HomeOfficeDeduction`, `Tax::DueDates.quarter_on`: unit specs.
- `Tax::Inputs`: excludes the personal book; nets collected sales tax; respects the period cutoffs; includes archived businesses with activity.
- Models: validations in §3.1; `estimate_ready?`; nullify on transaction destroy.
- Request specs per controller (§6.1): no household access → 404; viewer/accountant can read taxes but writes → 403; business owner edits only their own business's home office; a person's user edits only their own adjustments; the household owner edits everything; personal-book home office → 404; inaccessible transaction id → 404; the accountant's payment log omits the personal-book transaction.
- Views: the IRS link has `target="_blank"` and `rel="noopener noreferrer"` and uses the household URL.
- System spec: record a payment by searching for and picking the IRS debit, and see the due amount drop.
- `spec/db/seeds_spec.rb`: the 2026 row is `estimate_ready?` after seeding and seeding twice keeps edits.

## 11. Demo seed

`DemoSeeder` adds, for the current year:
- `ensure_tax_parameters` copies the full parameter set (not just the mileage rate) when it fills a missing year.
- A `TaxYear` with prior-year total tax and AGI.
- A simplified home office on the owner's business.
- Adjustments: SE health insurance for the owner, a SEP contribution for the spouse.
- "IRS USATAXPYMT" debits in joint checking on each installment due date already past, each linked to an `EstimatedPayment`, so the next installment shows as due.

## 12. Parent spec amendments

In `2026-10-05-goodbooks-design.md`:
- §9: replace with a pointer to this spec and a one-paragraph summary.
- §3 Authorization: household-level data is edited by the household owner, except a business's home office (also its business owner) and a person's adjustments (also that person's user).

In `docs/roadmap.md`: sub-project 6's Design and Documents rows point here; the "exclude the personal book from every estimate" hand-off is covered by §4.1 and §6.1; status moves per the convention.
