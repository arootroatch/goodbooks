# goodbooks — Design Spec

Date: 2026-10-05
Status: Draft for review

## 1. Purpose

goodbooks is a self-hosted, Dockerized replacement for the parts of QuickBooks one freelancing household actually uses. One person (the household owner) manages the books for their own and their spouse's freelance businesses, sees each business on its own and the household rolled up, estimates federal quarterly taxes for a married-filing-jointly return, and gives their accountant read access.

### Success criteria

- Bank and card activity arrives automatically (Plaid) or through CSV import, and the owner can categorize it quickly through a rules-driven inbox.
- Cash and other off-account expenses can be entered by hand.
- Deductible mileage is logged manually and valued at the IRS standard rate.
- Invoices are recorded and their payment status tracked (not generated or sent).
- Tennessee sales tax collected is tracked per filing period, kept out of income, and reconciled against remittances.
- The app tells the household how much federal estimated tax to pay each quarter, and why.
- The accountant can log in, see everything, and export what they need without being able to change anything.
- Running it is `docker compose up` on a home server behind a tunnel.

### Context and constraints (from the owner)

- Tax situation: US federal only. Tennessee has no personal income tax, and both businesses are sole proprietorships (no TN franchise & excise). Schedule C. Filing status is married filing jointly. No W-2 or other household income.
- Each bank or card account belongs to exactly one book: a business, or the household's single personal book (see `2026-10-06-goodbooks-tithing-design.md`). No account mixes personal and business activity.
- One household per install. Not multi-tenant SaaS.
- Hosted on a home server and exposed through Cloudflare Tunnel or Tailscale Funnel, so it is reachable from the internet.

### Explicit non-goals

Invoice generation or sending, payroll, inventory, double-entry ledger, accrual accounting, state income/franchise/business tax, sales tax for states other than Tennessee, sales tax computation rules (single-article cap, per-item exemptions), economic-nexus tracking, tax credits, itemized deductions, AMT, non-business income for tax purposes (the personal book tracks personal cash flow and tithe only), depreciation schedules / Section 179, the actual-expense vehicle method, GPS mileage tracking, entity types other than sole proprietorship, filing statuses other than MFJ, and multiple households.

## 2. Stack

- Ruby (latest stable 3.x), Rails 8.x (latest stable), Hotwire (Turbo + Stimulus), Propshaft, Importmap.
- SQLite in WAL mode for the primary DB and for Solid Queue / Solid Cache / Solid Cable.
- Rails 8 authentication generator + `rotp` for TOTP 2FA.
- Active Record Encryption for secrets at rest (Plaid access tokens, TOTP secrets).
- Active Storage on local disk (invoice PDFs, CSV uploads).
- RSpec, FactoryBot, Capybara (headless Chrome) for system specs, WebMock (all real HTTP blocked in tests).
- Docker: Rails 8 default Dockerfile (Thruster + Puma), `docker-compose.yml` with one `app` service and one named volume mounted at `/rails/storage`.

## 3. Cross-cutting rules

### Money

- All money is stored as signed integers of cents in columns named `*_cents`. Never floats, never decimals.
- A `Money` value object (pure Ruby, no gem) wraps cents, formats for display (`$1,234.56`, negatives as `-$1,234.56`), and parses user input (`"1,234.5"` → 123450). Invalid input is a validation error, not a silent zero.
- Percentages are stored as integer basis points (`5000` = 50%, `9235` = 92.35%).
- Calculations that apply a rate use `Rational` arithmetic and round half-up to whole cents once, at the end of each line item. Rounding happens in exactly one helper, `Money.round_rational`.
- Mileage is stored as integer tenths of a mile (`miles_tenths`). The mileage rate is stored as integer tenths of a cent (e.g. 72.5¢ → `725`).

### Sign convention

- `Transaction#amount_cents` is from the account's point of view: positive = money into the account, negative = money out.
- Importers normalize to this convention (Plaid reports outflows as positive and must be inverted; CSV mappings carry an "invert sign" flag for card statements).
- Category totals are the sum of signed amounts. Reports display expense totals as positive numbers (negated sum), so a refund in an expense category reduces that expense.

### Authorization

- Every business-scoped query goes through `Current.user.accessible_businesses` (businesses where the user has a membership). A record in a business the user cannot access returns 404, not 403.
- Write actions check the role through a single `Authorization` concern (hand-rolled, no Pundit): `viewer` reads only, `editor` reads and writes data, `owner` also manages the business's settings, accounts, and members.
- Household-level screens (household rollup, tax estimates, people, tax years) are visible only to users with at least viewer access on **every** business in the household. Editing household-level data requires `household_owner`.

### Seeds

- `db/seeds.rb`: reference data for every environment, idempotent: `TaxParameters` for the current tax year and the default Schedule C category template.
- `bin/rails demo:seed`: development/demo data. Raises in production. Creates a household with two people (owner + spouse), three users (owner, spouse as editor of her business and viewer of his, accountant as viewer of both), two businesses, one CSV account and one manual Cash account per business, about 12 months of realistic categorized and uncategorized transactions, rules, mileage entries, and (as later sub-projects land) invoices, fake-Plaid accounts, tax year inputs, home office, and adjustments. All demo users share the password `password` and a fixed TOTP secret. The task prints the logins and the secret when it finishes.
- `bin/rails demo:reset`: drop, create, migrate, seed, demo:seed.
- Every sub-project that adds a model extends `demo:seed` in the same change.

### Testing

- TDD throughout: write the failing spec first.
- Pure services (`Money`, `RuleEngine`, `CsvImport::Parser`, report calculators, `Tax::Estimator`) get exhaustive unit specs with no database.
- Every controller gets request specs covering: non-member → 404, viewer cannot write, editor can write data but not settings, owner can do everything.
- System specs cover the CSV import preview, the categorization inbox, the invite flow, and the 2FA login.
- Test output must be clean: no log lines, deprecation warnings, or console noise in a passing run.

## 4. Decomposition

Seven sub-projects, built in order. Each gets its own implementation plan.

1. **Core**: auth + 2FA, household/people/businesses/memberships, invite links, manual and CSV accounts, transactions, categories, rules + inbox, mileage, reports, backups, demo seed, Docker.
2. **Invoices**
3. **Personal book + tithing** (spec: `2026-10-06-goodbooks-tithing-design.md`)
4. **Sales tax** (Tennessee)
5. **Plaid**
6. **Tax engine**: quarterly estimates, home office, per-person adjustments.
7. **Sharing polish**: email delivery of invites, session management, audit log.

Sections 5–10 describe sub-projects 1, 2 and 4–7; sub-project 3 has its own spec.

## 5. Sub-project 1: Core

### 5.1 Data model

```
Household             name                                  (exactly one row)
Person                household, name, user (nullable)       taxpayer: owner or spouse; max 2
User                  email, password_digest, name, household_owner:boolean,
                      otp_secret (encrypted), otp_enabled_at, recovery_code_digests (json)
Session               user, ip, user_agent, last_seen_at     (Rails 8 generator)
Business              household, person (owner taxpayer), name, archived_at
Membership            user, business, role: owner|editor|viewer   unique(user, business)
Invite                created_by (user), email (optional), token_digest, expires_at,
                      accepted_at, accepted_by; has_many InviteGrants
InviteGrant           invite, business, role
Account               business, name, source: manual|csv|plaid, kind: checking|savings|credit|cash|other,
                      csv_mapping (json, nullable), archived_at
Transaction           account, date, amount_cents, payee, memo, category (nullable),
                      transfer:boolean, excluded:boolean, external_id (nullable),
                      categorized_by: rule|user|nil, rule (nullable)
                      unique(account, external_id) where external_id not null
Category              business, name, kind: income|expense, schedule_c_line (string code),
                      deductible_bps (default 10000), archived_at
Rule                  business, position, field: payee|memo, operator: contains|equals|starts_with,
                      value, amount_min_cents, amount_max_cents (both nullable),
                      action: categorize|transfer, category (when categorize)
MileageEntry          business, date, purpose, from_location, to_location, miles_tenths, round_trip:boolean
TaxParameters         year, standard_mileage_rate_tenth_cents, (more fields added in sub-project 6)
CsvImport             account, uploaded file (Active Storage), status: previewed|committed|discarded,
                      row_count, new_count, duplicate_count, committed_at
```

Notes:

- `Person` is a taxpayer, separate from `User`. The accountant is a `User` with no `Person`. The spouse is a `Person` who may or may not also be a `User`. Each business belongs to one `Person`; self-employment tax is computed per person in sub-project 6.
- A transaction is in the **inbox** when `category_id IS NULL AND transfer = false AND excluded = false`.
- `transfer` covers card payoffs, moves between own accounts, and owner draws/contributions. Transfers are excluded from income and expense.
- `excluded` hides an imported transaction (duplicate, junk) without deleting it, so re-imports don't bring it back.
- Creating a business auto-creates a manual account named "Cash" and copies the default category template into the business.
- Default category template: the Schedule C income lines (gross receipts, returns/allowances, other income) and expense lines 8–27 (advertising, car & truck, commissions, contract labor, insurance, legal/professional, office expense, rent, repairs, supplies, taxes & licenses, travel, meals at 5000 bps, utilities, wages, other: software, phone/internet, bank fees, education). Users can add, rename, and archive categories. `schedule_c_line` is chosen from a fixed list.

### 5.2 Auth and first run

- If no `Household` exists, every route redirects to `/setup`. Setup creates the household, the first user (`household_owner: true`), that user's `Person`, and the spouse `Person` (optional, name only). Then it requires 2FA enrollment. After that, `/setup` returns 404 forever.
- Login: email + password, then a TOTP code or a recovery code. 2FA is mandatory for every user. A user without `otp_enabled_at` is forced into enrollment (QR code + manual key, confirm with one code, show 10 recovery codes once; recovery codes are stored as digests and are single use).
- `rate_limit` on the login and the TOTP endpoints: 10 attempts per 3 minutes per IP.
- Sessions are DB-backed (generator default), with a 30-day cookie.

### 5.3 Invite links (core version)

- The household owner, or an owner of a business, creates an invite: an optional email plus one or more (business, role) grants. Business owners can only grant on businesses they own.
- The app generates a random token, stores its digest, and shows the full URL once for copy/paste. Expiry is 7 days, single use.
- Accepting: if the visitor is logged in, grants are added to their memberships. Otherwise they create an account (email prefilled if given), enroll in 2FA, and receive the grants.
- The household owner may link an accepted user to a `Person` (used to connect the spouse's login to her taxpayer record).
- Email delivery arrives in sub-project 7.

### 5.4 Accounts and transactions

- Owners create, rename, and archive accounts. Archived accounts are hidden from lists but remain in reports.
- **Manual accounts**: editors add, edit, and delete transactions freely.
- **Imported transactions** (CSV, Plaid): `date`, `amount_cents`, and `payee` are read-only. Category, transfer, memo, and excluded are editable.
- Transaction list per account and per business: filters by date range, category, inbox status, and text search on payee/memo. Paginated.

### 5.5 CSV import

Two steps, so nothing lands in the books unseen.

1. **Upload + map.** The user uploads a file to an account. If the account has no saved `csv_mapping`, they map columns: date column + date format (from a fixed list), payee column, optional memo column, and either one amount column or separate debit/credit columns, plus an "invert sign" checkbox. They can skip N header rows. The mapping is saved on the account.
2. **Preview.** `CsvImport::Parser` (pure) turns rows into normalized transaction attributes plus per-row errors. Each row's `external_id` = SHA256 of `account_id | date | amount_cents | normalized payee | occurrence index`, where the occurrence index counts identical (date, amount, payee) rows earlier in the same file. This makes re-importing an overlapping statement idempotent while keeping genuine same-day duplicates. The preview shows new rows, duplicates (already present), and rows with errors (unparseable date or amount), along with the proposed rule categorization. The user confirms or discards.
3. **Commit** inserts new rows in one DB transaction, then runs the rule engine on them.

Encoding: UTF-8 with BOM tolerated. Max file size 5 MB.

### 5.6 Rules and the inbox

- `RuleEngine` is pure: given transaction attributes and an ordered list of rules, it returns the first match's action, or nil. Matching is case-insensitive. Payee/memo are whitespace-normalized. Amount bounds compare the absolute value of `amount_cents`.
- Rules run automatically on newly imported or synced transactions that are uncategorized. They never overwrite a user's categorization (`categorized_by: user`).
- The inbox (per business and household-wide) lists inbox transactions, newest first. Each row offers: category picker, "transfer", "exclude", and "make a rule from this" (a form prefilled with: payee contains <first word of the normalized payee> → chosen category; the user can edit the value before saving). Categorizing a row removes it from the list with Turbo, no page reload. "Apply rules to inbox" reruns the engine over the current inbox.
- Rules are ordered by `position` and reordered with drag or up/down buttons.

### 5.7 Mileage

- Editors log entries: date, purpose (required), from, to, miles (one decimal place), round-trip checkbox (doubles the miles).
- The deduction for a year = total `miles_tenths` × `TaxParameters(year).standard_mileage_rate_tenth_cents`, computed with `Rational` and rounded once. If that year's parameters are missing, the app shows a banner asking the household owner to enter the rate; it never guesses.

### 5.8 Reports

All reports take a date range (default: current calendar year to date) and apply to one business or the household rollup (household view subject to the household-screen rule in §3).

- **Profit & loss**: income categories, expense categories (with `deductible_bps` applied, showing both actual and deductible amounts), mileage deduction as its own line, net profit. Household view: one column per business plus a total.
- **Schedule C summary**: one business, one calendar year. Totals grouped by `schedule_c_line`, with mileage in line 9. Line 30 (home office) shows "—" until sub-project 6.
- **Mileage log**: an IRS-style table (date, purpose, from, to, miles) plus total and deduction. Exports as CSV, plus a print stylesheet so "Print → Save as PDF" produces a clean document.
- **Transaction export**: CSV of transactions in range: date, business, account, payee, memo, amount, category, Schedule C line, transfer, deductible amount.

Report math lives in pure calculator objects that take arrays of plain structs. Controllers load data and pass it in.

### 5.9 Backups

A Solid Queue recurring job runs nightly at 03:00 and uses SQLite's online backup API to write `storage/backups/goodbooks-YYYY-MM-DD.sqlite3`, keeping the most recent 14. The README documents copying the volume offsite.

### 5.10 Deployment

- `docker-compose.yml`: `app` (built from the Dockerfile), port 80 → Thruster, volume `goodbooks_storage:/rails/storage`, `restart: unless-stopped`.
- Required env: `RAILS_MASTER_KEY`, `APP_HOST`. Later sub-projects add `PLAID_*` and `SMTP_*`.
- TLS terminates at the tunnel. `config.assume_ssl = true`, `force_ssl = true`, and `hosts` restricted to `APP_HOST`.
- The DB is migrated on container start (Rails default `bin/docker-entrypoint`).
- The README covers Cloudflare Tunnel and Tailscale Funnel setup.

## 6. Sub-project 2: Invoices

Cash basis: invoices never count as income. Income comes only from categorized deposits.

```
Client          business, name, email (optional), notes, archived_at
Invoice         business, client, number (unique per business), issue_date, due_date,
                amount_cents, description, status: draft|sent|paid|void, paid_on, pdf (Active Storage, optional)
InvoicePayment  invoice, transaction (a deposit in the same business), amount_cents
```

- `outstanding_cents` = invoice amount − sum of its payments. When outstanding reaches 0, the status automatically becomes `paid`, with `paid_on` = latest linked deposit date. Removing a payment reverts the invoice to `sent`.
- An allocation's `amount_cents` defaults to min(outstanding, the deposit's unallocated amount). One deposit can pay several invoices. A deposit's total allocations can never exceed its amount.
- Overdue is derived (`sent` and `due_date` < today), not stored. Partial status is derived (`sent` with at least one payment).
- When an editor categorizes a positive transaction into an income category, the app suggests open invoices in that business whose outstanding balance is ≥ the unallocated deposit amount (exact match first) and offers a one-click link.
- Views: invoice list per business and household, filterable by status. Aging summary (current, 1–30, 31–60, 60+ days past due). CSV export.

## 7. Sub-project 4: Sales tax (Tennessee)

The app records sales tax; it does not compute it per item or act as a point of sale. Collected tax is a liability, not income. Remittances are not expenses. Gross receipts on the P&L, Schedule C, and the tax engine exclude collected sales tax, and remittances are not deducted (the "exclude from both" method).

### 7.1 Data model

```
SalesTaxProfile  business (unique), tn_account_number, filing_frequency: monthly|quarterly|annual,
                 default_rate_bps (state 7% + local), active:boolean
Transaction      + sales_channel: direct_tn|invoiced|marketplace|out_of_state (nullable; income only),
                 + sales_tax_cents (default 0), + destination_state (2-letter, out_of_state only),
                 + sales_tax_period (nullable; set on remittances)
Invoice          + sales_tax_cents (default 0; part of amount_cents)
Category         kind gains a third value: sales_tax_remittance (one per business, auto-created
                 when a SalesTaxProfile is activated; not on Schedule C)
SalesTaxPeriod   business, starts_on, ends_on, due_on, status: open|filed|paid, filed_on,
                 confirmation_number                     unique(business, starts_on)
```

### 7.2 Recording collected tax

- Only businesses with an active `SalesTaxProfile` show sales tax fields.
- **Direct TN** (POS payouts, direct deposits): the editor enters `sales_tax_cents` from their processor report, or clicks "tax-inclusive at default rate", which sets tax = amount × r / (1 + r) via `Money.round_rational`. The value stays editable to cover the single-article cap and exemptions.
- **Invoiced**: linking an `InvoicePayment` to a deposit sets the deposit's `sales_tax_cents` += payment amount × (invoice sales tax / invoice amount), rounded once per payment. The channel becomes `invoiced`.
- **Marketplace**: tagged `marketplace`, `sales_tax_cents` stays 0 (the facilitator remitted it). Reported separately for reconciliation.
- **Out of state**: tagged `out_of_state` with `destination_state`, `sales_tax_cents` 0.
- Validation: `sales_tax_cents` ≥ 0 and < `amount_cents`, and only on positive transactions in income categories.
- Rules gain an optional `sales_channel` to set when they categorize (e.g. payee contains "ETSY" → Sales, marketplace).

### 7.3 Periods and remittance

- Periods are generated from the profile's filing frequency (calendar months, quarters, or year). `due_on` = the 20th of the month after the period ends, rolled forward past weekends and state holidays.
- A transaction in the `sales_tax_remittance` category is linked to a period (default: the most recent period that is filed or past due and not paid).
- **Period report**: gross sales (all income in the period, including tax), marketplace sales, out-of-state sales, TN taxable sales (direct TN + invoiced, excluding tax), tax collected, remitted, and balance owed (collected − remitted). The editor marks the period filed (date + confirmation number). It becomes paid when remitted ≥ collected.
- A dashboard card per business shows the next due date and the current open balance. Overdue unfiled periods show a banner.
- Income totals across P&L, Schedule C, and the tax engine use `amount_cents − sales_tax_cents`. The `sales_tax_remittance` category is excluded from expenses. Report calculators get specs that prove both.
- `demo:seed` gives one business an active profile (quarterly), a mix of direct, invoiced, and marketplace sales, and one filed + paid period.

## 8. Sub-project 5: Plaid

- `Plaid::Client` is a thin wrapper over the official `plaid` Ruby gem, exposing `create_link_token`, `exchange_public_token`, `accounts`, `transactions_sync(cursor)`, `item_remove`, and webhook verification. Specs use `FakePlaidClient`, injected through configuration.
- `PlaidItem`: household, institution name, `access_token` (encrypted), `item_id`, `cursor`, status: `ok | login_required | error`, last_synced_at, last_error.
- Linking flow (business owner): Plaid Link in the browser via a Stimulus controller → token exchange on the server → the user picks which Plaid accounts to import and assigns each to one of their businesses → `Account` rows with `source: plaid` and `plaid_account_id`.
- `Plaid::Sync` processes `transactions/sync` pages: `added` → insert (external_id = Plaid `transaction_id`, amount sign inverted, pending transactions skipped until posted); `modified` → update date/amount/payee unless the row is excluded; `removed` → soft-exclude. If the user had categorized a removed transaction, it is flagged for review instead. The rule engine runs on inserted rows.
- `PlaidSyncJob` runs daily via recurring schedule, on the `SYNC_UPDATES_AVAILABLE` webhook, and from a manual "Sync now" button. Retries use exponential backoff (5 attempts).
- `ITEM_LOGIN_REQUIRED` (from an error or webhook) → item status `login_required`, with a banner offering re-link via Link update mode.
- Webhooks: `POST /plaid/webhooks`, verified with Plaid's JWT verification (`Plaid-Verification` header, key fetched via `webhook_verification_key/get` and cached). Unverified requests get 401.
- Env: `PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ENV` (sandbox|production). Without them, Plaid UI is hidden.
- `demo:seed` creates a fake Plaid item and account with synced-looking transactions (no network).

## 9. Sub-project 6: Tax engine (federal, MFJ, sole proprietors)

### 9.1 Inputs

```
TaxParameters (per year; seeded, editable by household owner):
  standard_mileage_rate_tenth_cents, standard_deduction_mfj_cents,
  brackets_mfj (json: [{floor_cents, rate_bps}]), ss_wage_base_cents,
  se_earnings_bps (9235), ss_rate_bps (1240), medicare_rate_bps (290),
  additional_medicare_bps (90), additional_medicare_threshold_mfj_cents,
  qbi_bps (2000), qbi_threshold_mfj_cents, home_office_simplified_rate_cents (500),
  home_office_simplified_max_sqft (300), retirement limit fields for SEP and Solo 401k,
  safe_harbor_high_agi_threshold_cents (15000000)
TaxYear         household, year, prior_year_total_tax_cents, prior_year_agi_cents
EstimatedPayment tax_year, quarter (1–4), paid_on, amount_cents
HomeOffice      business, year, method: simplified|regular, office_sqft, home_sqft,
                rent_cents, mortgage_interest_cents, utilities_cents, insurance_cents,
                repairs_cents, other_cents, depreciation_cents (accountant-provided)
PersonAdjustment person, year, se_health_insurance_cents, retirement_contribution_cents,
                retirement_plan: sep|solo_401k
```

The seeded values for the current year are entered from IRS publications (the annual inflation-adjustment Rev. Proc., the IRS mileage notice, and the SSA wage base announcement) at implementation time and verified against those sources.

### 9.2 Calculation (`Tax::Estimator`, pure)

For a tax year, as of a quarter:

1. **Net profit per business** = income (net of collected sales tax, §7) − deductible expenses (with `deductible_bps` applied) − mileage deduction − home office deduction.
   - Simplified home office: min(office_sqft, max_sqft) × rate.
   - Regular: (office_sqft / home_sqft) × sum of home costs + depreciation.
   - Either way, capped at the business's profit before home office (no loss created). The excess is reported as carryover, informational only.
2. **Annualize** YTD figures using the Form 2210 Schedule AI periods: Q1 = Jan–Mar (×4), Q2 = Jan–May (×2.4), Q3 = Jan–Aug (×1.5), Q4 = full year (×1). Done with `Rational`.
3. **SE tax per person**: SE earnings = sum of the person's businesses' net profit × 92.35%. Below $400, SE tax is 0. SS portion = 12.4% × min(SE earnings, wage base). Medicare = 2.9% × SE earnings. Household Additional Medicare = 0.9% × max(0, total SE earnings − threshold).
4. **Income tax (household)**: AGI = total net profit − ½ of the SE tax (excluding Additional Medicare) − SE health insurance − retirement contributions. SE health insurance is capped per person at that person's net profit minus their ½ SE tax and retirement contribution. Taxable income before QBI = AGI − standard deduction (floored at 0). QBI deduction = 20% × min(QBI, taxable income before QBI), where QBI = total net profit − ½ SE tax − SE health insurance − retirement. If taxable income before QBI exceeds the QBI threshold, a warning says the simplified QBI may be wrong. Tax = brackets applied to taxable income.
5. **Total projected tax** = income tax + SE tax + Additional Medicare.
6. **Required annual payment** = min(90% of projected tax, safe harbor), where safe harbor = 100% of prior-year total tax, or 110% if prior-year AGI > $150,000. Safe harbor is omitted if prior-year values are missing (with a banner asking for them).
7. **Per-quarter amounts**, shown side by side:
   - Regular installment: required annual × cumulative 25/50/75/100% − payments made so far.
   - Annualized installment: annualized projected tax (steps 1–5 run on the annualized figures) × the Schedule AI applicable percentage for the period (22.5%, 45%, 67.5%, 90%; these already include the 90% factor) − payments made so far.
   - The "pay at least" figure = the lesser of the two, floored at 0. It is labeled an approximation of the Form 2210 rules.
8. **Due dates**: Apr 15, Jun 15, Sep 15 of the year and Jan 15 of the next, rolled forward past weekends and federal holidays (holiday list in code, per year).

### 9.3 Screens

- A tax year dashboard: due now, next due date, both methods, per-person SE breakdown, an expandable line-by-line worksheet showing every intermediate number, the payment log, and the warnings.
- Edit screens for TaxYear, TaxParameters, HomeOffice (per business), and PersonAdjustment (per person).
- The Schedule C report fills line 30 from HomeOffice.
- A permanent note on the screen: this is an estimate; verify with your accountant.

### 9.4 Testing

`Tax::Estimator` gets worked examples computed by hand and checked into the specs: zero profit, profit under $400, one spouse above the wage base, both spouses, Additional Medicare threshold crossed, safe harbor at 100% vs 110%, each annualization period, home office capped by profit, SE health insurance cap, and payments that exceed the requirement.

## 10. Sub-project 7: Sharing polish

- **Email delivery**: when `SMTP_*` env vars are set, invites with an email are sent via Action Mailer (deliver_later). Otherwise the copy-link flow from Core remains.
- **Session management**: each user sees their active sessions (device, IP, last seen) and can revoke them. The household owner can revoke all sessions for any user and remove a user's memberships.
- **Audit log**: an `AuditEvent` (user, action, record type/id, changed attributes as before/after JSON, created_at) is written for creates, updates, and deletes of transactions, categories, rules, mileage entries, invoices, payments, sales tax periods, tax inputs, memberships, and invites. Viewable by the household owner, filterable by user, record type, and date. No editing or deletion of audit events.
