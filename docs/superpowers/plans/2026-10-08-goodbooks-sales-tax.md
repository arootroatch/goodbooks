# goodbooks Sales Tax (Sub-project 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record the Tennessee sales tax one business collects (direct Stripe sales and invoiced sales), record Stripe processor fees on deposits, keep collected tax out of income, and show each filing period's figures, due date, and status (open, due, overdue, filed, paid).

**Architecture:** Taxability lives on income categories (`sales_tax_treatment: taxable | exempt | not_a_sale`). Transactions carry only `sales_tax_cents` (direct tax) and `processor_fee_cents`, and each `InvoicePayment` stores its pro-rated share of the invoice's tax, so nothing is ever incremented in place. Filing periods come from a pure `SalesTax::Calendar`, and only filings are stored. `SalesTax::PeriodReport` (pure) computes every figure and status on each request, and `Reports::CategoryTotals` is the single place where income becomes "net of tax, gross of fees".

**Tech Stack:** Ruby 4.0.7, Rails 8.1.4, SQLite, Hotwire, RSpec, FactoryBot, Capybara (rack_test), Brakeman, bundler-audit, RuboCop (rails-omakase), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-08-goodbooks-sales-tax-design.md` (parent: `docs/superpowers/specs/2026-10-05-goodbooks-design.md` §3 cross-cutting rules; invoices: `docs/superpowers/specs/2026-10-06-goodbooks-invoices-design.md`).

## Prerequisites (before Task 1)

- `export PATH="$HOME/.rubies/ruby-4.0.7/bin:$PATH"` before every command (`ruby -v` → `ruby 4.0.7`).
- Work in the worktree `/Users/AlexRoot-Roatch/current-projects/goodbooks-sales-tax`, branch `sales-tax` (cut from `tithing`; holds the spec commit). The PR's base is `tithing` (stacked on PR #7), not `main`.
- `bundle install` (the 4.0.7 gem set may be missing `rspec-rails`, `rqrcode`, `image_processing`), then `bin/rails db:test:prepare`.
- `bundle exec rspec` → `N examples, 0 failures` with no other output. Record N as the baseline. If the suite isn't green, stop and report.

## Global Constraints

- Money is signed integer cents in `*_cents` columns. Display it with `money(cents)`, parse input with `Money.parse` / `money_attribute`, and round only through `Money.round_rational`. Never use floats.
- `Transaction#amount_cents`: positive = money into the account. A deposit's **gross** = `amount_cents + processor_fee_cents`. Its **total tax** = `sales_tax_cents` + the sum of its invoice payments' `sales_tax_cents`. Its **net income** = gross − total tax.
- Rates are integer basis points (`925` = 9.25%). `default_rate_bps` is in `1..2000`.
- Tax-inclusive tax = `Money.round_rational(Rational(base × rate_bps, 10_000 + rate_bps))`, rounded once. The base is the deposit's **unallocated** gross.
- An invoice payment's tax share = `Money.round_rational(Rational(payment × invoice tax, invoice amount))`, rounded once per payment. The payment that completes the invoice takes `invoice tax − earlier shares`.
- Due date = the 20th of the month after the period ends, rolled forward past Saturdays, Sundays, and the three TN state holidays that can fall on a 20th (MLK Day, Presidents' Day, Good Friday), which `SalesTax::Holidays` computes by rule for any year. No holiday list is maintained.
- Periods and statuses are never stored. Only `SalesTaxFiling` rows (period start, filed_on, confirmation number) are.
- Never name an association, method, or local `transaction`. DB transactions use `ApplicationRecord.transaction` (or `with_lock`).
- Non-member → 404 (lookups go through `Current.user.accessible_businesses`). Viewer writing → 403 (`require_editor!`). Owner-only → 403 (`require_owner!`). Every sales tax screen on the personal book → 404 (`BusinessKindOnly`). A sales tax period URL that isn't a period start in the business's calendar → 404.
- Strong params never list a `*_id` key. `sales_tax_period_starts_on` is a date string, not an id.
- `config.action_controller.raise_on_missing_callback_actions = true` in test: every `only:`/`except:` list must name existing actions.
- Exact user-facing messages (specs match them):
  - "Clear the processor fee first."
  - "Clear the sales tax first."
  - "This invoice includes sales tax — categorize the deposit as a taxable sale."
  - "Unlink payments before changing sales tax."
  - "Filings or remittances exist for the current periods."
  - "Sales tax isn't set up for this business."
- Test output must stay clean: a passing `bundle exec rspec` prints only the reporter.
- TDD: each task writes its failing spec first and runs it to see it fail.
- Formatting: single spaces in literals, no column alignment. `bin/rubocop` must pass after every task.
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- **Parallel branch:** `plaid` is built at the same time from `tithing`. It also edits the `transactions` table, `app/models/transaction.rb`, `lib/demo_seeder.rb`, the dashboard, `app/views/inboxes/_row.html.erb`, `db/schema.rb`, and `docs/roadmap.md`. Keep edits to those files small and additive (new columns, new methods, new lines; no reformatting). Whichever of `sales-tax` / `plaid` merges second rebases onto the other and resolves the conflicts. For `db/schema.rb`, re-run `bin/rails db:migrate` after the rebase rather than hand-merging.
- Kaneo: the controlling session (not task implementers) comments progress on GB-4 ("Phase 4: Sales tax (Tennessee)", task id `qkzmh9eae5pdu8oo6tgb7fqa`) after each task and moves it to In Review when the PR opens.

## Review Focus

1. **A Stripe payout linked with its fee and an untouched amount field**: a $970.70 deposit plus a $29.30 fee typed on Record payment, with the prefilled $970.70 amount left alone, pays a $1,000.00 invoice in full rather than leaving $29.30 open. (Pinned in Task 6.)
2. **Taxed deposits reclassified from the inbox endpoint**: marking a deposit with sales tax as a transfer or excluded, or moving it to an exempt category through `ClassificationsController`, gives a flash with "Clear the sales tax first.", not a 500, and nothing changes. (Pinned in Task 12.)
3. **Hand-typed period URLs**: `/sales_tax/periods/2026-07-02`, `/sales_tax/periods/abc`, a period before the profile's start, a future period, and any period on a business whose profile is inactive → 404, never 500. (Pinned in Task 11.)
4. **Rate input variants**: `9.25`, `9.25%`, and `7` save; `9.255`, `0`, `20.01`, `abc`, and blank give a form error with the old rate kept. (Pinned in Task 10.)
5. **Fee and tax typos on the transaction form**: `-5`, `abc`, and `1,00` show field errors; blank saves as 0. (Pinned in Task 12.)

## File Map

```
db/migrate/20261009000001_add_sales_tax_fields_to_categories.rb       (Task 1)
app/models/category.rb, category_template.rb                          (Tasks 1, 5)
app/models/sales_tax/holidays.rb, sales_tax/calendar.rb               pure (Task 2)
app/models/sales_tax/inclusive_tax.rb, sales_tax/period_report.rb     pure (Task 3)
db/migrate/20261009000002_create_sales_tax_profiles_and_filings.rb    (Task 4)
app/models/sales_tax_profile.rb, sales_tax_filing.rb, business.rb     (Task 4)
spec/factories/sales_tax_profiles.rb, sales_tax_filings.rb            (Task 4)
db/migrate/20261009000003_add_sales_tax_amounts.rb                    (Task 5)
app/models/transaction.rb                                             (Tasks 5, 6, 9, 12)
app/models/invoices/allocation.rb, invoice_matcher.rb, services/invoice_payments.rb,
  controllers/invoice_payments_controller.rb, views/invoice_payments/_deposits.html.erb   (Task 6)
app/models/invoices/tax_share.rb, invoice.rb, invoices controller/form/show/_payments     (Task 7)
app/models/reports/category_totals.rb, reports/transaction_csv.rb, two export controllers (Task 8)
app/models/sales_tax.rb, sales_tax/entries.rb, sales_tax/remittance_period.rb             (Task 9)
config/routes.rb, controllers/sales_tax_profiles_controller.rb, views/sales_tax_profiles/show.html.erb,
  helpers/sales_tax_helper.rb, businesses/_nav, categories controller/form/index           (Task 10)
controllers/concerns/sales_tax_period_lookup.rb, sales_tax_periods_controller.rb,
  sales_tax_filings_controller.rb, views/sales_tax_periods/show.html.erb, reports/sales_tax_period_csv.rb (Task 11)
transactions controller/form/index, transaction_filter.rb, categories_helper.rb,
  rules/_form, inboxes/_row                                                               (Task 12)
dashboards controller/view, businesses controller/show, views/sales_tax/_summary, _overdue_banner (Task 13)
lib/demo_seeder.rb, spec/lib/demo_seeder_spec.rb                      (Task 14)
spec/system/sales_tax_spec.rb, README.md, docs/roadmap.md             (Task 15)
```

---

### Task 1: Category sales tax treatment, remittance kind, Merchant fees

**Files:**
- Create: `db/migrate/20261009000001_add_sales_tax_fields_to_categories.rb`
- Modify: `app/models/category.rb`, `app/models/category_template.rb`, `spec/models/category_spec.rb`, `spec/services/business_provisioner_spec.rb`

**Interfaces:**
- Produces: columns `categories.sales_tax_treatment` (string, nullable) and `categories.processor_fees` (boolean, not null, default false); `Category::SALES_TAX_TREATMENTS` (`%w[taxable exempt not_a_sale]`); `Category::SALES_TAX_TREATMENT_LABELS`; the kind enum gains `sales_tax_remittance` (scope `Category.sales_tax_remittance`, predicate `#sales_tax_remittance?`); `Category#taxable?` and `Category#sale?`; scope `Category.taxable_gross_receipts`; a "Merchant fees" template category (expense, line 10, `processor_fees: true`).

- [ ] **Step 1: Write the failing specs**

Append inside the top-level `describe` of `spec/models/category_spec.rb`:

```ruby
  describe "sales tax treatment" do
    let(:business) { create(:business) }

    it "defaults income on line 1 to taxable and other income to not a sale" do
      expect(create(:category, :income, business: business).sales_tax_treatment).to eq("taxable")
      other = create(:category, business: business, kind: "income", schedule_c_line: "6")
      expect(other.sales_tax_treatment).to eq("not_a_sale")
    end

    it "keeps an explicit treatment and rejects unknown ones" do
      exempt = create(:category, :income, business: business, sales_tax_treatment: "exempt")
      expect(exempt.sales_tax_treatment).to eq("exempt")
      expect(exempt).not_to be_taxable
      expect(exempt).to be_sale
      expect(build(:category, :income, business: business, sales_tax_treatment: "wholesale")).not_to be_valid
    end

    it "clears the treatment on expense and personal categories" do
      expect(create(:category, business: business, sales_tax_treatment: "taxable").sales_tax_treatment).to be_nil
      book = create(:business, :personal)
      expect(create(:category, :income, business: book).sales_tax_treatment).to be_nil
    end

    it "clears the treatment when an income category becomes an expense" do
      category = create(:category, :income, business: business)
      category.update!(kind: "expense", schedule_c_line: "18")
      expect(category.sales_tax_treatment).to be_nil
    end
  end

  describe "sales tax remittance kind" do
    it "has no Schedule C line and belongs only to business books" do
      remittance = create(:category, kind: "sales_tax_remittance", schedule_c_line: "18")
      expect(remittance.schedule_c_line).to be_nil
      expect(remittance).to be_sales_tax_remittance
      expect(remittance).not_to be_income

      book = create(:business, :personal)
      personal = build(:category, business: book, kind: "sales_tax_remittance")
      expect(personal).not_to be_valid
      expect(personal.errors[:kind]).to include("can't be a sales tax remittance on the personal book")
    end

    it "allows one active remittance category per business" do
      first = create(:category, kind: "sales_tax_remittance", name: "Sales tax remittance")
      second = build(:category, business: first.business, kind: "sales_tax_remittance", name: "TN remittance")
      expect(second).not_to be_valid
      expect(second.errors[:kind]).to include("already has a sales tax remittance category")
      first.update!(archived_at: Time.current)
      expect(second).to be_valid
    end
  end

  describe "processor fees flag" do
    let(:business) { create(:business) }

    it "is allowed on one business expense category" do
      create(:category, business: business, name: "Merchant fees", schedule_c_line: "10", processor_fees: true)
      second = build(:category, business: business, name: "Stripe fees", schedule_c_line: "10", processor_fees: true)
      expect(second).not_to be_valid
      expect(second.errors[:processor_fees]).to include("is already set on another category")
    end

    it "is rejected on income and on the personal book" do
      expect(build(:category, :income, business: business, processor_fees: true)).not_to be_valid
      book = create(:business, :personal)
      expect(build(:category, business: book, processor_fees: true)).not_to be_valid
    end
  end
```

Append inside the `describe` of `spec/services/business_provisioner_spec.rb`:

```ruby
  it "adds Merchant fees as the processor-fee category" do
    business = BusinessProvisioner.call(build(:business), owner: create(:user))
    fees = business.categories.find_by!(processor_fees: true)
    expect([ fees.name, fees.kind, fees.schedule_c_line ]).to eq([ "Merchant fees", "expense", "10" ])
    expect(business.categories.find_by!(name: "Sales").sales_tax_treatment).to eq("taxable")
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/category_spec.rb spec/services/business_provisioner_spec.rb`
Expected: FAIL (`unknown attribute 'sales_tax_treatment'`, `'sales_tax_remittance' is not a valid kind`).

- [ ] **Step 3: Migration**

`db/migrate/20261009000001_add_sales_tax_fields_to_categories.rb`:

```ruby
class AddSalesTaxFieldsToCategories < ActiveRecord::Migration[8.1]
  class MigrationBusiness < ActiveRecord::Base
    self.table_name = "businesses"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  def up
    add_column :categories, :sales_tax_treatment, :string
    add_column :categories, :processor_fees, :boolean, null: false, default: false
    add_index :categories, :business_id, unique: true, where: "processor_fees", name: "index_categories_one_processor_fees_per_business"
    MigrationCategory.reset_column_information

    business_ids = MigrationBusiness.where(kind: "business").pluck(:id)
    income = MigrationCategory.where(business_id: business_ids, kind: "income")
    income.where(schedule_c_line: "1").update_all(sales_tax_treatment: "taxable")
    income.where(sales_tax_treatment: nil).update_all(sales_tax_treatment: "not_a_sale")

    business_ids.each do |business_id|
      existing = MigrationCategory.find_by(business_id: business_id, name: "Merchant fees")
      if existing
        existing.update_columns(processor_fees: true)
      else
        MigrationCategory.create!(business_id: business_id, name: "Merchant fees", kind: "expense", schedule_c_line: "10",
                                  deductible_bps: 10_000, processor_fees: true)
      end
    end
  end

  def down
    remove_index :categories, name: "index_categories_one_processor_fees_per_business"
    remove_column :categories, :processor_fees
    remove_column :categories, :sales_tax_treatment
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 4: Category model**

In `app/models/category.rb`:

1. Replace the enum line and add constants and a scope:

```ruby
  SALES_TAX_TREATMENTS = %w[taxable exempt not_a_sale].freeze
  SALES_TAX_TREATMENT_LABELS = { "taxable" => "Taxable sales", "exempt" => "Exempt sales", "not_a_sale" => "Not a sale" }.freeze

  belongs_to :business

  enum :kind, { income: "income", expense: "expense", sales_tax_remittance: "sales_tax_remittance" }, validate: true

  scope :active, -> { where(archived_at: nil) }
  scope :gross_receipts, -> { active.income.where(schedule_c_line: "1") }
  scope :taxable_gross_receipts, -> { gross_receipts.where(sales_tax_treatment: "taxable") }
```

2. Under the existing `validates :deductible_bps` line, add:

```ruby
  validates :sales_tax_treatment, inclusion: { in: SALES_TAX_TREATMENTS }, allow_nil: true
  validates :processor_fees, uniqueness: { scope: :business_id, message: "is already set on another category" }, if: :processor_fees?
```

3. After `before_validation :normalize_tithe_flags`, add `before_validation :normalize_sales_tax_fields`. After `validate :tithe_flags_only_on_personal`, add:

```ruby
  validate :remittance_only_on_business_books
  validate :one_active_remittance_category
  validate :processor_fees_only_on_business_expense
```

4. Public methods, next to `gross_receipts?`:

```ruby
  def taxable? = income? && sales_tax_treatment == "taxable"
  def sale? = income? && %w[taxable exempt].include?(sales_tax_treatment)
```

5. In `schedule_c_line_matches_kind`, insert `return if sales_tax_remittance?` right after the personal-book `if ... end` block (before `allowed = ...`).

6. Private methods:

```ruby
  # Taxability is only meaningful on business income; a remittance is never on Schedule C.
  def normalize_sales_tax_fields
    if income? && business&.business?
      self.sales_tax_treatment ||= schedule_c_line == "1" ? "taxable" : "not_a_sale"
    else
      self.sales_tax_treatment = nil
    end
    self.schedule_c_line = nil if sales_tax_remittance?
  end

  def remittance_only_on_business_books
    errors.add(:kind, "can't be a sales tax remittance on the personal book") if sales_tax_remittance? && business&.personal?
  end

  def one_active_remittance_category
    return unless sales_tax_remittance? && archived_at.nil? && business
    return unless business.categories.sales_tax_remittance.active.where.not(id: id).exists?

    errors.add(:kind, "already has a sales tax remittance category")
  end

  def processor_fees_only_on_business_expense
    return unless processor_fees? && (!expense? || business&.personal?)

    errors.add(:processor_fees, "only applies to business expense categories")
  end
```

- [ ] **Step 5: Template**

In `app/models/category_template.rb`, add after the "Commissions and fees" line:

```ruby
    { name: "Merchant fees", kind: "expense", schedule_c_line: "10", processor_fees: true },
```

- [ ] **Step 6: Run the specs**

Run: `bundle exec rspec spec/models/category_spec.rb spec/services/business_provisioner_spec.rb`
Expected: PASS. Then `bundle exec rspec` → baseline + new examples, 0 failures. Then `bin/rubocop`.

Check the backfill against development data:

```bash
bin/rails runner 'p Category.where(processor_fees: true).count == Business.business_kind.count; p Category.income.joins(:business).where(businesses: { kind: "business" }, sales_tax_treatment: nil).count'
```

Expected: `true`, then `0`.

- [ ] **Step 7: Commit**

```bash
git add db app/models/category.rb app/models/category_template.rb spec
git commit -m "Sales tax: category treatment, remittance kind, Merchant fees

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Pure filing calendar and TN holiday rules

**Files:**
- Create: `app/models/sales_tax/holidays.rb`, `app/models/sales_tax/calendar.rb`, `spec/models/sales_tax/holidays_spec.rb`, `spec/models/sales_tax/calendar_spec.rb`

**Interfaces:**
- Produces:
  - `SalesTax::Holidays.for(year)` → array of `Date`: MLK Day (3rd Monday of January), Presidents' Day (3rd Monday of February), and Good Friday (Easter − 2). Computed by rule for any year; never raises. Other TN state holidays are fixed or floating dates that can never be the 20th or the business day after a weekend-rolled 20th, so they are deliberately omitted.
  - `SalesTax::Calendar.new(starts_on:, frequency:, today:, holidays: SalesTax::Holidays)`, where `frequency` is `"monthly" | "quarterly" | "annual"`.
  - `#periods` → `Array<SalesTax::Calendar::Period>`, oldest first, from the period containing `starts_on` through the one containing `today`.
  - `#period_for(date)` → `Period` or nil (before the first period).
  - `#include_start?(date)` → boolean.
  - `SalesTax::Calendar.due_on(ends_on, holidays: SalesTax::Holidays)` → `Date`.
  - `Period = Data.define(:starts_on, :ends_on, :due_on)`, with `#label` ("Mar 2026", "Q1 2026", "2026"). `due_on` is always set.

- [ ] **Step 1: Write the failing specs**

`spec/models/sales_tax/holidays_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SalesTax::Holidays do
  {
    2025 => [ Date.new(2025, 1, 20), Date.new(2025, 2, 17), Date.new(2025, 4, 18) ],
    2026 => [ Date.new(2026, 1, 19), Date.new(2026, 2, 16), Date.new(2026, 4, 3) ],
    2027 => [ Date.new(2027, 1, 18), Date.new(2027, 2, 15), Date.new(2027, 3, 26) ],
    2057 => [ Date.new(2057, 1, 15), Date.new(2057, 2, 19), Date.new(2057, 4, 20) ]
  }.each do |year, dates|
    it "computes MLK Day, Presidents' Day, and Good Friday for #{year}" do
      expect(described_class.for(year)).to eq(dates)
    end
  end

  it "works for any year without a list" do
    expect(described_class.for(2199).size).to eq(3)
  end

  it "rolls real due dates past MLK Day, Presidents' Day, and Good Friday" do
    expect(SalesTax::Calendar.due_on(Date.new(2024, 12, 31))).to eq(Date.new(2025, 1, 21))
    expect(SalesTax::Calendar.due_on(Date.new(2034, 1, 31))).to eq(Date.new(2034, 2, 21))
    expect(SalesTax::Calendar.due_on(Date.new(2057, 3, 31))).to eq(Date.new(2057, 4, 23))
  end
end
```

`spec/models/sales_tax/calendar_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SalesTax::Calendar do
  def holidays(*dates)
    Object.new.tap do |list|
      list.define_singleton_method(:for) { |year| dates.select { _1.year == year } }
    end
  end

  def calendar(starts_on, frequency, today, list = holidays)
    described_class.new(starts_on: starts_on, frequency: frequency, today: today, holidays: list)
  end

  it "lists calendar quarters from the one containing the start through the one containing today" do
    periods = calendar(Date.new(2026, 2, 14), "quarterly", Date.new(2026, 10, 8)).periods
    expect(periods.map(&:starts_on)).to eq([ Date.new(2026, 1, 1), Date.new(2026, 4, 1), Date.new(2026, 7, 1), Date.new(2026, 10, 1) ])
    expect(periods.first.ends_on).to eq(Date.new(2026, 3, 31))
    expect(periods.map(&:label)).to eq([ "Q1 2026", "Q2 2026", "Q3 2026", "Q4 2026" ])
  end

  it "lists months and years" do
    months = calendar(Date.new(2026, 8, 31), "monthly", Date.new(2026, 10, 1)).periods
    expect(months.map { [ _1.starts_on, _1.ends_on ] }).to eq([
      [ Date.new(2026, 8, 1), Date.new(2026, 8, 31) ], [ Date.new(2026, 9, 1), Date.new(2026, 9, 30) ], [ Date.new(2026, 10, 1), Date.new(2026, 10, 31) ]
    ])
    expect(months.first.label).to eq("Aug 2026")
    years = calendar(Date.new(2025, 6, 1), "annual", Date.new(2026, 3, 1)).periods
    expect(years.map { [ _1.starts_on, _1.ends_on, _1.label ] }).to eq([
      [ Date.new(2025, 1, 1), Date.new(2025, 12, 31), "2025" ], [ Date.new(2026, 1, 1), Date.new(2026, 12, 31), "2026" ]
    ])
  end

  it "is empty when today is before the first period" do
    expect(calendar(Date.new(2026, 5, 1), "monthly", Date.new(2026, 4, 30)).periods).to eq([])
  end

  {
    "a weekday" => [ Date.new(2026, 9, 30), Date.new(2026, 10, 20) ],
    "a Saturday" => [ Date.new(2026, 5, 31), Date.new(2026, 6, 22) ],
    "a Sunday" => [ Date.new(2026, 8, 31), Date.new(2026, 9, 21) ]
  }.each do |label, (ends_on, due_on)|
    it "rolls a 20th that falls on #{label}" do
      expect(described_class.due_on(ends_on, holidays: holidays)).to eq(due_on)
    end
  end

  it "rolls past a holiday, and past a holiday followed by a weekend" do
    expect(described_class.due_on(Date.new(2026, 9, 30), holidays: holidays(Date.new(2026, 10, 20)))).to eq(Date.new(2026, 10, 21))
    expect(described_class.due_on(Date.new(2026, 10, 31), holidays: holidays(Date.new(2026, 11, 20)))).to eq(Date.new(2026, 11, 23))
  end

  it "finds the period for a date and recognizes period starts" do
    cal = calendar(Date.new(2026, 1, 1), "quarterly", Date.new(2026, 10, 8))
    expect(cal.period_for(Date.new(2026, 5, 9)).starts_on).to eq(Date.new(2026, 4, 1))
    expect(cal.period_for(Date.new(2025, 12, 31))).to be_nil
    expect(cal.include_start?(Date.new(2026, 4, 1))).to be(true)
    expect(cal.include_start?(Date.new(2026, 4, 2))).to be(false)
    expect(cal.include_start?(Date.new(2025, 10, 1))).to be(false)
    expect(cal.include_start?(nil)).to be(false)
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/sales_tax`
Expected: FAIL (`uninitialized constant SalesTax`).

- [ ] **Step 3: Holiday rules**

`app/models/sales_tax/holidays.rb`:

```ruby
module SalesTax
  # The Tennessee state holidays that can delay a sales tax due date. Returns are due on the 20th, rolled past
  # weekends and holidays; only MLK Day (Jan 15–21), Presidents' Day (Feb 15–21), and Good Friday (Mar 20–Apr 23)
  # can land on a 20th. Every other TN holiday is a fixed date other than the 20th or falls nowhere near it.
  module Holidays
    module_function

    def for(year)
      [ nth_monday(year, 1, 3), nth_monday(year, 2, 3), easter(year) - 2 ]
    end

    def nth_monday(year, month, n)
      first = Date.new(year, month, 1)
      first + ((1 - first.wday) % 7) + 7 * (n - 1)
    end

    # Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
    def easter(year)
      a = year % 19
      b, c = year.divmod(100)
      d, e = b.divmod(4)
      g = (8 * b + 13) / 25
      h = (19 * a + b - d - g + 15) % 30
      i, k = c.divmod(4)
      l = (32 + 2 * e + 2 * i - h - k) % 7
      m = (a + 11 * h + 22 * l) / 451
      month, day = (h + l - 7 * m + 114).divmod(31)
      Date.new(year, month, day + 1)
    end
  end
end
```

- [ ] **Step 4: Calendar**

`app/models/sales_tax/calendar.rb`:

```ruby
module SalesTax
  # Filing periods for a sales tax profile. Pure: dates in, periods out.
  class Calendar
    MONTHS = { "monthly" => 1, "quarterly" => 3, "annual" => 12 }.freeze

    Period = Data.define(:starts_on, :ends_on, :due_on) do
      def label
        months = (ends_on.year * 12 + ends_on.month) - (starts_on.year * 12 + starts_on.month) + 1
        case months
        when 1 then starts_on.strftime("%b %Y")
        when 3 then "Q#{(starts_on.month - 1) / 3 + 1} #{starts_on.year}"
        else starts_on.year.to_s
        end
      end
    end

    def self.due_on(ends_on, holidays: Holidays)
      date = ends_on.next_day.change(day: 20)
      date += 1 while date.saturday? || date.sunday? || holidays.for(date.year).include?(date)
      date
    end

    def initialize(starts_on:, frequency:, today:, holidays: Holidays)
      @months = MONTHS.fetch(frequency)
      @first = period_start(starts_on)
      @today = today
      @holidays = holidays
    end

    def periods
      starts = []
      start = @first
      while start <= @today
        starts << start
        start = start.advance(months: @months)
      end
      starts.map { build(_1) }
    end

    def period_for(date)
      start = period_start(date)
      start < @first ? nil : build(start)
    end

    def include_start?(date) = !date.nil? && date >= @first && period_start(date) == date

    private

    def period_start(date)
      Date.new(date.year, (date.month - 1) / @months * @months + 1, 1)
    end

    def build(start)
      ends_on = start.advance(months: @months) - 1
      Period.new(starts_on: start, ends_on: ends_on, due_on: self.class.due_on(ends_on, holidays: @holidays))
    end
  end
end
```

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/models/sales_tax` → PASS. `bin/rubocop`.

- [ ] **Step 6: Commit**

```bash
git add app/models/sales_tax spec/models/sales_tax
git commit -m "Sales tax: pure filing calendar and TN holiday rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Pure tax-inclusive helper and period report

**Files:**
- Create: `app/models/sales_tax/inclusive_tax.rb`, `app/models/sales_tax/period_report.rb`, `spec/models/sales_tax/inclusive_tax_spec.rb`, `spec/models/sales_tax/period_report_spec.rb`

**Interfaces:**
- Consumes: `SalesTax::Calendar::Period` (Task 2).
- Produces:
  - `SalesTax::InclusiveTax.call(gross_cents:, rate_bps:)` → Integer cents (0 for a non-positive base).
  - `SalesTax::PeriodReport.new(period:, deposits:, remittances:, filing:, today:)`, where:
    - `deposits` are `SalesTax::PeriodReport::Deposit(posted_on, treatment, gross_cents, total_tax_cents, source = nil)`;
    - `remittances` are `SalesTax::PeriodReport::Remittance(posted_on, amount_cents, period_starts_on, source = nil)`;
    - `filing` is any object or nil.
    
    It filters deposits to the period's dates and remittances to `period_starts_on == period.starts_on`, and exposes `#period`, `#filing`, `#deposits`, `#remittances`, `#gross_sales_cents`, `#exempt_sales_cents`, `#taxable_sales_cents`, `#tax_collected_cents`, `#remitted_cents`, `#balance_cents`, `#filed?`, `#paid?`, and `#status` (`"open" | "due" | "overdue" | "filed" | "paid"`).

- [ ] **Step 1: Write the failing specs**

`spec/models/sales_tax/inclusive_tax_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SalesTax::InclusiveTax do
  it "backs the tax out of a tax-inclusive gross" do
    expect(described_class.call(gross_cents: 100_000, rate_bps: 925)).to eq(8_467)
    expect(described_class.call(gross_cents: 10_925, rate_bps: 925)).to eq(925)
  end

  it "rounds half up once" do
    expect(described_class.call(gross_cents: 3, rate_bps: 10_000)).to eq(2)
  end

  it "is zero for an empty or negative base" do
    expect(described_class.call(gross_cents: 0, rate_bps: 925)).to eq(0)
    expect(described_class.call(gross_cents: -500, rate_bps: 925)).to eq(0)
  end
end
```

`spec/models/sales_tax/period_report_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SalesTax::PeriodReport do
  let(:period) do
    SalesTax::Calendar::Period.new(starts_on: Date.new(2026, 4, 1), ends_on: Date.new(2026, 6, 30), due_on: Date.new(2026, 7, 20))
  end
  let(:deposits) do
    [
      described_class::Deposit.new(posted_on: Date.new(2026, 4, 1), treatment: "taxable", gross_cents: 100_000, total_tax_cents: 8_467),
      described_class::Deposit.new(posted_on: Date.new(2026, 6, 30), treatment: "exempt", gross_cents: 50_000, total_tax_cents: 0),
      described_class::Deposit.new(posted_on: Date.new(2026, 7, 1), treatment: "taxable", gross_cents: 99_999, total_tax_cents: 999),
      described_class::Deposit.new(posted_on: Date.new(2026, 3, 31), treatment: "taxable", gross_cents: 99_999, total_tax_cents: 999)
    ]
  end
  let(:remittances) do
    [
      described_class::Remittance.new(posted_on: Date.new(2026, 7, 15), amount_cents: -8_000, period_starts_on: Date.new(2026, 4, 1)),
      described_class::Remittance.new(posted_on: Date.new(2026, 5, 15), amount_cents: -9_999, period_starts_on: Date.new(2026, 1, 1))
    ]
  end
  let(:filing) { Object.new }

  def report(today:, filing: nil, remitted: remittances)
    described_class.new(period: period, deposits: deposits, remittances: remitted, filing: filing, today: today)
  end

  it "computes every figure from the period's own deposits and remittances" do
    r = report(today: Date.new(2026, 7, 16))
    expect(r.gross_sales_cents).to eq(150_000)
    expect(r.exempt_sales_cents).to eq(50_000)
    expect(r.taxable_sales_cents).to eq(91_533)
    expect(r.tax_collected_cents).to eq(8_467)
    expect(r.remitted_cents).to eq(8_000)
    expect(r.balance_cents).to eq(467)
    expect(r.deposits.size).to eq(2)
    expect(r.remittances.size).to eq(1)
  end

  it "derives the status" do
    expect(report(today: Date.new(2026, 6, 30)).status).to eq("open")
    expect(report(today: Date.new(2026, 7, 1)).status).to eq("due")
    expect(report(today: Date.new(2026, 7, 20)).status).to eq("due")
    expect(report(today: Date.new(2026, 7, 21)).status).to eq("overdue")
    expect(report(today: Date.new(2026, 7, 21), filing: filing).status).to eq("filed")
    paid = [ described_class::Remittance.new(posted_on: Date.new(2026, 7, 15), amount_cents: -8_467, period_starts_on: period.starts_on) ]
    expect(report(today: Date.new(2026, 7, 21), filing: filing, remitted: paid)).to be_paid
  end

  it "treats an overpayment as paid with a negative balance" do
    over = [ described_class::Remittance.new(posted_on: Date.new(2026, 7, 15), amount_cents: -9_000, period_starts_on: period.starts_on) ]
    r = report(today: Date.new(2026, 7, 21), filing: filing, remitted: over)
    expect(r.balance_cents).to eq(-533)
    expect(r.status).to eq("paid")
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/sales_tax/inclusive_tax_spec.rb spec/models/sales_tax/period_report_spec.rb`
Expected: FAIL (`uninitialized constant SalesTax::InclusiveTax`).

- [ ] **Step 3: Implement**

`app/models/sales_tax/inclusive_tax.rb`:

```ruby
module SalesTax
  # Tax inside a tax-inclusive amount: base × r / (1 + r), rounded once.
  module InclusiveTax
    def self.call(gross_cents:, rate_bps:)
      return 0 unless gross_cents.positive?

      Money.round_rational(Rational(gross_cents * rate_bps, 10_000 + rate_bps))
    end
  end
end
```

`app/models/sales_tax/period_report.rb`:

```ruby
module SalesTax
  # Figures and status for one filing period (spec §5.2). Pure: structs in, numbers out.
  class PeriodReport
    Deposit = Data.define(:posted_on, :treatment, :gross_cents, :total_tax_cents, :source) do
      def initialize(posted_on:, treatment:, gross_cents:, total_tax_cents:, source: nil) = super
    end

    Remittance = Data.define(:posted_on, :amount_cents, :period_starts_on, :source) do
      def initialize(posted_on:, amount_cents:, period_starts_on:, source: nil) = super
    end

    attr_reader :period, :filing, :deposits, :remittances

    def initialize(period:, deposits:, remittances:, filing:, today:)
      @period = period
      @filing = filing
      @today = today
      dates = period.starts_on..period.ends_on
      @deposits = deposits.select { dates.cover?(_1.posted_on) }.sort_by(&:posted_on)
      @remittances = remittances.select { _1.period_starts_on == period.starts_on }.sort_by(&:posted_on)
    end

    def gross_sales_cents = deposits.sum(&:gross_cents)
    def exempt_sales_cents = deposits.select { _1.treatment == "exempt" }.sum(&:gross_cents)
    def taxable_sales_cents = deposits.select { _1.treatment == "taxable" }.sum { _1.gross_cents - _1.total_tax_cents }
    def tax_collected_cents = deposits.sum(&:total_tax_cents)
    def remitted_cents = -remittances.sum(&:amount_cents)
    def balance_cents = tax_collected_cents - remitted_cents

    def filed? = !filing.nil?
    def paid? = status == "paid"

    def status
      if filed? then balance_cents <= 0 ? "paid" : "filed"
      elsif @today > period.due_on then "overdue"
      elsif @today > period.ends_on then "due"
      else "open"
      end
    end
  end
end
```

- [ ] **Step 4: Run the specs**

Run: `bundle exec rspec spec/models/sales_tax` → PASS. `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add app/models/sales_tax spec/models/sales_tax
git commit -m "Sales tax: pure tax-inclusive helper and period report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Sales tax profile and filings

**Files:**
- Create: `db/migrate/20261009000002_create_sales_tax_profiles_and_filings.rb`, `app/models/sales_tax_profile.rb`, `app/models/sales_tax_filing.rb`, `spec/factories/sales_tax_profiles.rb`, `spec/factories/sales_tax_filings.rb`, `spec/models/sales_tax_profile_spec.rb`, `spec/models/sales_tax_filing_spec.rb`
- Modify: `app/models/business.rb`

**Interfaces:**
- Consumes: `SalesTax::Calendar` (Task 2); `Category.sales_tax_remittance` (Task 1).
- Produces:
  - `SalesTaxProfile`: `business`, `tn_account_number`, `filing_frequency`, `default_rate_bps`, `starts_on`, `active`.
    - `SalesTaxProfile::FREQUENCIES`
    - `#default_rate_percent` / `#default_rate_percent=` (accepts "9.25", "9.25%", "7")
    - `#calendar(today: Date.current)` → `SalesTax::Calendar`
    - private `#calendar_in_use?` (Task 9 extends it)
    - saving an active profile creates the business's remittance category once
  - `SalesTaxFiling`: `business`, `period_starts_on`, `filed_on`, `confirmation_number`.
  - `Business#sales_tax_profile` (has_one), `Business#sales_tax_filings` (has_many), `Business#collects_sales_tax?`.
  - Factories: `:sales_tax_profile` (quarterly, 925, `starts_on` 2026-01-01, active) and `:sales_tax_filing` (its business has a profile; `period_starts_on` 2026-01-01).

- [ ] **Step 1: Write the failing specs**

`spec/factories/sales_tax_profiles.rb`:

```ruby
FactoryBot.define do
  factory :sales_tax_profile do
    business
    filing_frequency { "quarterly" }
    default_rate_bps { 925 }
    starts_on { Date.new(2026, 1, 1) }
    active { true }
  end
end
```

`spec/factories/sales_tax_filings.rb`:

```ruby
FactoryBot.define do
  factory :sales_tax_filing do
    business { association(:sales_tax_profile).business }
    period_starts_on { Date.new(2026, 1, 1) }
    filed_on { Date.new(2026, 4, 15) }
  end
end
```

`spec/models/sales_tax_profile_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SalesTaxProfile do
  let(:business) { create(:business) }

  it "is valid with the defaults and makes the business collect sales tax" do
    profile = create(:sales_tax_profile, business: business)
    expect(business.reload).to be_collects_sales_tax
    profile.update!(active: false)
    expect(business.reload).not_to be_collects_sales_tax
  end

  it "belongs only to business books, one per business" do
    expect(build(:sales_tax_profile, business: create(:business, :personal))).not_to be_valid
    create(:sales_tax_profile, business: business)
    expect(build(:sales_tax_profile, business: business)).not_to be_valid
  end

  { "9.25" => 925, "9.25%" => 925, "7" => 700, "0.01" => 1, "20" => 2_000 }.each do |input, bps|
    it "parses a rate of #{input}" do
      profile = build(:sales_tax_profile, business: business, default_rate_percent: input)
      expect(profile).to be_valid
      expect(profile.default_rate_bps).to eq(bps)
    end
  end

  [ "9.255", "0", "20.01", "abc", "" ].each do |input|
    it "rejects a rate of #{input.inspect}" do
      expect(build(:sales_tax_profile, business: business, default_rate_percent: input)).not_to be_valid
    end
  end

  it "shows the rate as a percent" do
    expect(build(:sales_tax_profile, default_rate_bps: 925).default_rate_percent).to eq("9.25")
    expect(build(:sales_tax_profile, default_rate_bps: 700).default_rate_percent).to eq("7")
  end

  it "rejects a future start date and an unknown frequency" do
    expect(build(:sales_tax_profile, business: business, starts_on: Date.current + 1)).not_to be_valid
    expect(build(:sales_tax_profile, business: business, filing_frequency: "weekly")).not_to be_valid
  end

  it "creates the remittance category once, on first activation" do
    profile = create(:sales_tax_profile, business: business, active: false)
    expect(business.categories.sales_tax_remittance).to be_empty
    profile.update!(active: true)
    profile.update!(active: false)
    profile.update!(active: true)
    expect(business.categories.sales_tax_remittance.pluck(:name)).to eq([ "Sales tax remittance" ])
  end

  it "uses a different name when a category already has it" do
    create(:category, business: business, name: "Sales tax remittance")
    create(:sales_tax_profile, business: business)
    expect(business.categories.sales_tax_remittance.pluck(:name)).to eq([ "Sales tax remittance (TN)" ])
  end

  it "builds a calendar from the frequency and start date" do
    profile = build(:sales_tax_profile, starts_on: Date.new(2026, 2, 3), filing_frequency: "monthly")
    expect(profile.calendar(today: Date.new(2026, 3, 1)).periods.map(&:starts_on)).to eq([ Date.new(2026, 2, 1), Date.new(2026, 3, 1) ])
  end

  it "locks the frequency and start date once a period is filed" do
    profile = create(:sales_tax_profile, business: business)
    expect(profile.update(filing_frequency: "monthly")).to be(true)
    profile.update!(filing_frequency: "quarterly")
    create(:sales_tax_filing, business: business)
    expect(profile.reload.update(filing_frequency: "monthly")).to be(false)
    expect(profile.errors[:base]).to include("Filings or remittances exist for the current periods.")
    expect(profile.reload.update(starts_on: Date.new(2026, 4, 1))).to be(false)
    expect(profile.reload.update(default_rate_bps: 975)).to be(true)
  end
end
```

`spec/models/sales_tax_filing_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SalesTaxFiling do
  it "is valid for a period start in the business's calendar" do
    expect(build(:sales_tax_filing)).to be_valid
  end

  it "rejects a date that isn't a period start, a future filing date, and a second filing" do
    filing = create(:sales_tax_filing)
    expect(build(:sales_tax_filing, business: filing.business, period_starts_on: Date.new(2026, 2, 1))).not_to be_valid
    expect(build(:sales_tax_filing, business: filing.business, period_starts_on: Date.new(2026, 4, 1), filed_on: Date.current + 1)).not_to be_valid
    duplicate = build(:sales_tax_filing, business: filing.business)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:period_starts_on]).to include("is already filed")
  end

  it "needs a sales tax profile" do
    filing = build(:sales_tax_filing, business: create(:business))
    expect(filing).not_to be_valid
    expect(filing.errors[:period_starts_on]).to include("isn't a filing period for this business")
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/sales_tax_profile_spec.rb spec/models/sales_tax_filing_spec.rb`
Expected: FAIL (`uninitialized constant SalesTaxProfile`).

- [ ] **Step 3: Migration**

`db/migrate/20261009000002_create_sales_tax_profiles_and_filings.rb`:

```ruby
class CreateSalesTaxProfilesAndFilings < ActiveRecord::Migration[8.1]
  def change
    create_table :sales_tax_profiles do |t|
      t.references :business, null: false, foreign_key: true, index: { unique: true }
      t.string :tn_account_number
      t.string :filing_frequency, null: false, default: "quarterly"
      t.integer :default_rate_bps, null: false
      t.date :starts_on, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :sales_tax_filings do |t|
      t.references :business, null: false, foreign_key: true
      t.date :period_starts_on, null: false
      t.date :filed_on, null: false
      t.string :confirmation_number
      t.timestamps
    end
    add_index :sales_tax_filings, %i[business_id period_starts_on], unique: true
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 4: Models**

`app/models/sales_tax_profile.rb`:

```ruby
class SalesTaxProfile < ApplicationRecord
  FREQUENCIES = %w[monthly quarterly annual].freeze
  REMITTANCE_CATEGORY_NAME = "Sales tax remittance".freeze

  belongs_to :business

  validates :business_id, uniqueness: true
  validates :filing_frequency, inclusion: { in: FREQUENCIES }
  validates :default_rate_bps, numericality: { only_integer: true, in: 1..2_000, message: "must be between 0.01% and 20%" }
  validates :starts_on, presence: true
  validates :tn_account_number, length: { maximum: 50 }
  validate :business_kind_only
  validate :starts_on_not_in_future
  validate :default_rate_percent_parses
  validate :calendar_unchanged_once_used, on: :update

  after_save :ensure_remittance_category, if: :active?

  def calendar(today: Date.current)
    SalesTax::Calendar.new(starts_on: starts_on, frequency: filing_frequency, today: today)
  end

  def default_rate_percent
    return @default_rate_percent_input if defined?(@default_rate_percent_input)
    return if default_rate_bps.nil?

    value = Rational(default_rate_bps, 100)
    value.denominator == 1 ? value.to_i.to_s : format("%.2f", value)
  end

  def default_rate_percent=(input)
    @default_rate_percent_input = input
    stripped = input.to_s.strip.delete_suffix("%").strip
    @default_rate_percent_invalid = !stripped.match?(/\A\d{1,2}(\.\d{1,2})?\z/)
    self.default_rate_bps = @default_rate_percent_invalid ? nil : (Rational(stripped) * 100).round
  end

  private

  def business_kind_only
    errors.add(:business, "must be a business, not the personal book") if business&.personal?
  end

  def starts_on_not_in_future
    errors.add(:starts_on, "can't be in the future") if starts_on && starts_on > Date.current
  end

  def default_rate_percent_parses
    errors.add(:default_rate_percent, "is not a percentage like 9.25") if @default_rate_percent_invalid
  end

  def calendar_unchanged_once_used
    return unless will_save_change_to_filing_frequency? || will_save_change_to_starts_on?

    errors.add(:base, "Filings or remittances exist for the current periods.") if calendar_in_use?
  end

  def calendar_in_use? = business.sales_tax_filings.exists?

  def ensure_remittance_category
    return if business.categories.sales_tax_remittance.exists?

    name = business.categories.exists?(name: REMITTANCE_CATEGORY_NAME) ? "#{REMITTANCE_CATEGORY_NAME} (TN)" : REMITTANCE_CATEGORY_NAME
    business.categories.create!(name: name, kind: "sales_tax_remittance")
  end
end
```

`app/models/sales_tax_filing.rb`:

```ruby
class SalesTaxFiling < ApplicationRecord
  belongs_to :business

  validates :period_starts_on, :filed_on, presence: true
  validates :period_starts_on, uniqueness: { scope: :business_id, message: "is already filed" }
  validates :confirmation_number, length: { maximum: 100 }
  validate :filed_on_not_in_future
  validate :period_in_calendar

  private

  def filed_on_not_in_future
    errors.add(:filed_on, "can't be in the future") if filed_on && filed_on > Date.current
  end

  def period_in_calendar
    return if period_starts_on.nil? || business.nil?

    calendar = business.sales_tax_profile&.calendar
    errors.add(:period_starts_on, "isn't a filing period for this business") unless calendar&.include_start?(period_starts_on)
  end
end
```

In `app/models/business.rb`, add after `has_many :transactions, through: :accounts`:

```ruby
  has_one :sales_tax_profile, dependent: :destroy
  has_many :sales_tax_filings, dependent: :destroy
```

and, before `private`:

```ruby
  def collects_sales_tax? = business? && sales_tax_profile&.active? == true
```

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/models/sales_tax_profile_spec.rb spec/models/sales_tax_filing_spec.rb spec/models/business_spec.rb` → PASS. Then `bundle exec rspec` and `bin/rubocop`.

- [ ] **Step 6: Commit**

```bash
git add db app/models spec
git commit -m "Sales tax: profile with calendar and remittance category, filings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Fee and direct-tax amounts on transactions, with guards

**Files:**
- Create: `db/migrate/20261009000003_add_sales_tax_amounts.rb`, `spec/models/transaction_sales_tax_spec.rb`
- Modify: `app/models/transaction.rb`, `app/models/category.rb`, `spec/models/category_spec.rb`

**Interfaces:**
- Consumes: `Category#taxable?` (Task 1); `Business#collects_sales_tax?` (Task 4).
- Produces:
  - Columns:
    - `transactions.sales_tax_cents` (int, not null, default 0)
    - `transactions.processor_fee_cents` (int, not null, default 0)
    - `transactions.sales_tax_period_starts_on` (date)
    - `invoices.sales_tax_cents` (int, not null, default 0)
    - `invoice_payments.sales_tax_cents` (int, not null, default 0)
  - `money_attribute :sales_tax` and `:processor_fee` on `Transaction` (blank → 0).
  - `Transaction#gross_cents`, `#invoice_tax_cents`, `#total_sales_tax_cents`, `#net_income_cents`.
  - `Transaction::INVOICE_TAX_SQL`, `Transaction::TAXED_SQL` (SQL fragments over `transactions`).
  - Category guards: treatment can't leave `taxable` while taxed deposits exist; kind can't change while deposits carry fees.

- [ ] **Step 1: Write the failing specs**

`spec/models/transaction_sales_tax_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Transaction, "sales tax and processor fees" do
  let(:business) { create(:business) }
  let!(:profile) { create(:sales_tax_profile, business: business) }
  let(:account) { create(:account, business: business) }
  let(:sales) { create(:category, :income, business: business, name: "Sales") }
  let(:consulting) { create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt") }
  let(:payout) { create(:transaction, account: account, amount_cents: 97_070, payee: "STRIPE", category: sales) }

  it "derives gross, total tax, and net income" do
    payout.update!(processor_fee_cents: 2_930, sales_tax_cents: 8_467)
    expect(payout.gross_cents).to eq(100_000)
    expect(payout.total_sales_tax_cents).to eq(8_467)
    expect(payout.net_income_cents).to eq(91_533)
  end

  it "saves blank fee and tax inputs as zero and rejects bad ones" do
    expect(payout.update(processor_fee: "", sales_tax: "")).to be(true)
    expect([ payout.processor_fee_cents, payout.sales_tax_cents ]).to eq([ 0, 0 ])
    expect(payout.update(processor_fee: "abc")).to be(false)
    expect(payout.errors[:processor_fee]).to include("is not a valid amount")
    expect(payout.reload.update(processor_fee: "-5")).to be(false)
    expect(payout.errors[:processor_fee]).to include("can't be negative")
    expect(payout.reload.update(sales_tax: "-5")).to be(false)
    expect(payout.errors[:sales_tax]).to include("can't be negative")
  end

  describe "processor fee" do
    it "is allowed on uncategorized and income deposits" do
      expect(create(:transaction, account: account, amount_cents: 5_000, processor_fee_cents: 175)).to be_persisted
      expect(payout.update(processor_fee_cents: 2_930)).to be(true)
    end

    it "only applies to money in" do
      txn = build(:transaction, account: account, amount_cents: -5_000, processor_fee_cents: 100)
      expect(txn).not_to be_valid
      expect(txn.errors[:processor_fee]).to include("only applies to money in")
    end

    it "isn't used on the personal book" do
      book = create(:business, :personal)
      txn = build(:transaction, account: create(:account, business: book), amount_cents: 5_000, processor_fee_cents: 100)
      expect(txn).not_to be_valid
      expect(txn.errors[:processor_fee]).to include("isn't used on the personal book")
    end

    it "must be cleared before the deposit becomes a transfer, excluded, or an expense" do
      payout.update!(processor_fee_cents: 2_930)
      [ { transfer: true }, { excluded: true }, { category: create(:category, business: business) } ].each do |attrs|
        expect(payout.reload.update(attrs)).to be(false), "accepted #{attrs.keys.first}"
        expect(payout.errors[:base]).to include("Clear the processor fee first.")
      end
    end
  end

  describe "direct sales tax" do
    it "is allowed on a taxable deposit and must stay below gross" do
      expect(payout.update(sales_tax_cents: 8_467)).to be(true)
      expect(payout.update(sales_tax_cents: 97_070)).to be(false)
      expect(payout.errors[:sales_tax]).to include("must be less than the gross amount $970.70")
    end

    it "needs an active sales tax profile" do
      profile.update!(active: false)
      expect(payout.update(sales_tax_cents: 100)).to be(false)
      expect(payout.errors[:sales_tax]).to include("needs an active sales tax profile")
    end

    it "is kept when the profile is later deactivated" do
      payout.update!(sales_tax_cents: 100)
      profile.update!(active: false)
      expect(payout.reload.update(memo: "kept")).to be(true)
    end

    it "only applies to money in, in a taxable category" do
      out = build(:transaction, account: account, amount_cents: -5_000, sales_tax_cents: 100)
      expect(out).not_to be_valid
      expect(out.errors[:sales_tax]).to include("only applies to money in")
      exempt = build(:transaction, account: account, amount_cents: 5_000, category: consulting, sales_tax_cents: 100)
      expect(exempt).not_to be_valid
      expect(exempt.errors[:base]).to include("Clear the sales tax first.")
      uncategorized = build(:transaction, account: account, amount_cents: 5_000, sales_tax_cents: 100)
      expect(uncategorized).not_to be_valid
    end

    it "must be cleared before the deposit becomes a transfer, excluded, or non-taxable" do
      payout.update!(sales_tax_cents: 8_467)
      [ { transfer: true }, { excluded: true }, { category: consulting }, { category: nil } ].each do |attrs|
        expect(payout.reload.update(attrs)).to be(false), "accepted #{attrs.inspect}"
        expect(payout.errors[:base]).to include("Clear the sales tax first.")
      end
    end

    it "counts invoice tax shares toward the total and the guards" do
      invoice = create(:invoice, business: business, amount_cents: 97_070)
      create(:invoice_payment, invoice: invoice, deposit: payout, amount_cents: 97_070, sales_tax_cents: 8_000)
      expect(payout.reload.total_sales_tax_cents).to eq(8_000)
      expect(payout.update(category: consulting)).to be(false)
      expect(payout.errors[:base]).to include("Clear the sales tax first.")
    end
  end

  describe "category guards" do
    it "keeps a taxable category taxable while its deposits carry tax" do
      payout.update!(sales_tax_cents: 100)
      expect(sales.update(sales_tax_treatment: "exempt")).to be(false)
      expect(sales.errors[:sales_tax_treatment]).to include("can't change while deposits in this category carry sales tax")
      payout.update!(sales_tax_cents: 0)
      expect(sales.update(sales_tax_treatment: "exempt")).to be(true)
    end

    it "keeps an income category income while its deposits carry fees" do
      payout.update!(processor_fee_cents: 2_930)
      expect(consulting.update(kind: "expense", schedule_c_line: "18")).to be(true)
      expect(sales.update(kind: "expense", schedule_c_line: "18")).to be(false)
      expect(sales.errors[:kind]).to include("can't change while deposits in this category carry processor fees")
    end
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/models/transaction_sales_tax_spec.rb`
Expected: FAIL (`unknown attribute 'sales_tax_cents'`).

- [ ] **Step 3: Migration**

`db/migrate/20261009000003_add_sales_tax_amounts.rb`:

```ruby
class AddSalesTaxAmounts < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :sales_tax_cents, :integer, null: false, default: 0
    add_column :transactions, :processor_fee_cents, :integer, null: false, default: 0
    add_column :transactions, :sales_tax_period_starts_on, :date
    add_column :invoices, :sales_tax_cents, :integer, null: false, default: 0
    add_column :invoice_payments, :sales_tax_cents, :integer, null: false, default: 0
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 4: Transaction model**

In `app/models/transaction.rb`:

1. Below `UNALLOCATED_SQL`, add:

```ruby
  INVOICE_TAX_SQL = "COALESCE((SELECT SUM(invoice_payments.sales_tax_cents) FROM invoice_payments " \
                    "WHERE invoice_payments.deposit_id = transactions.id), 0)".freeze
  TAXED_SQL = "transactions.sales_tax_cents > 0 OR #{INVOICE_TAX_SQL} > 0".freeze
```

2. Below `money_attribute :amount`, add:

```ruby
  money_attribute :sales_tax, allow_blank: true
  money_attribute :processor_fee, allow_blank: true
```

3. After `validate :linked_deposit_stays_payable, on: :update`, add:

```ruby
  validate :processor_fee_allowed
  validate :sales_tax_allowed
```

4. After `before_validation :clear_category_for_transfer`, add `before_validation :default_sales_amounts`.

5. Public methods, after `unallocated_cents`:

```ruby
  def gross_cents = amount_cents.to_i + processor_fee_cents.to_i

  def invoice_tax_cents
    invoice_payments.loaded? ? invoice_payments.sum(&:sales_tax_cents) : invoice_payments.sum(:sales_tax_cents)
  end

  def total_sales_tax_cents = sales_tax_cents.to_i + (new_record? ? 0 : invoice_tax_cents)
  def net_income_cents = gross_cents - total_sales_tax_cents
```

6. Private methods:

```ruby
  def default_sales_amounts
    self.sales_tax_cents ||= 0
    self.processor_fee_cents ||= 0
  end

  def processor_fee_allowed
    fee = processor_fee_cents.to_i
    return errors.add(:processor_fee, "can't be negative") if fee.negative?
    return if fee.zero?

    if account&.business&.personal? then errors.add(:processor_fee, "isn't used on the personal book")
    elsif amount_cents.to_i <= 0 then errors.add(:processor_fee, "only applies to money in")
    elsif transfer? || excluded? || (category && !category.income?) then errors.add(:base, "Clear the processor fee first.")
    end
  end

  def sales_tax_allowed
    direct = sales_tax_cents.to_i
    return errors.add(:sales_tax, "can't be negative") if direct.negative?

    total = total_sales_tax_cents
    return if total.zero?

    if direct.positive? && will_save_change_to_sales_tax_cents? && !account&.business&.collects_sales_tax?
      errors.add(:sales_tax, "needs an active sales tax profile")
    elsif amount_cents.to_i <= 0 then errors.add(:sales_tax, "only applies to money in")
    elsif transfer? || excluded? || !category&.taxable? then errors.add(:base, "Clear the sales tax first.")
    elsif total >= gross_cents then errors.add(:sales_tax, "must be less than the gross amount #{Money.new(gross_cents)}")
    end
  end
```

- [ ] **Step 5: Category guards**

In `app/models/category.rb`, after `validate :kind_stays_income_while_linked, on: :update`, add:

```ruby
  validate :treatment_stays_taxable_while_taxed, on: :update
  validate :kind_stays_while_fees, on: :update
```

Private methods:

```ruby
  def treatment_stays_taxable_while_taxed
    return unless sales_tax_treatment_was == "taxable" && will_save_change_to_sales_tax_treatment?
    return unless Transaction.where(category_id: id).where(Transaction::TAXED_SQL).exists?

    errors.add(:sales_tax_treatment, "can't change while deposits in this category carry sales tax")
  end

  def kind_stays_while_fees
    return unless will_save_change_to_kind? && Transaction.where(category_id: id).where("transactions.processor_fee_cents > 0").exists?

    errors.add(:kind, "can't change while deposits in this category carry processor fees")
  end
```

- [ ] **Step 6: Run the specs**

Run: `bundle exec rspec spec/models/transaction_sales_tax_spec.rb spec/models/category_spec.rb spec/models/transaction_spec.rb spec/models/transaction_linked_deposit_spec.rb` → PASS. Then `bundle exec rspec` and `bin/rubocop`.

- [ ] **Step 7: Commit**

```bash
git add db app/models spec
git commit -m "Sales tax: fee and direct tax on transactions, with guards

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Invoice allocation against gross, fee on Record payment

**Files:**
- Modify: `app/models/transaction.rb`, `app/models/invoices/allocation.rb`, `app/models/invoice_matcher.rb`, `app/services/invoice_payments.rb`, `app/controllers/invoice_payments_controller.rb`, `app/views/invoice_payments/_deposits.html.erb`, `spec/models/invoices/allocation_spec.rb`, `spec/models/invoice_matcher_spec.rb`, `spec/models/transaction_linked_deposit_spec.rb`, `spec/services/invoice_payments_spec.rb`, `spec/requests/invoice_payments_spec.rb`

**Interfaces:**
- Consumes: `Transaction#gross_cents`, `processor_fee_cents` (Task 5).
- Produces:
  - `Transaction#unallocated_cents` = gross − allocated; `UNALLOCATED_SQL` is gross-based.
  - `Invoices::Allocation.call(invoice_amount_cents:, invoice_paid_cents:, deposit_gross_cents:, deposit_allocated_cents:, requested_cents: nil)` (the keyword was `deposit_amount_cents`).
  - `InvoicePayments.link(invoice:, deposit:, amount_cents: nil, category: nil, processor_fee_cents: nil)`.
  - Record payment form params: `processor_fee` (string) and `proposed_amount` (string; when it equals `amount` and a fee is given, the amount is recomputed).

- [ ] **Step 1: Write the failing specs**

In `spec/models/invoices/allocation_spec.rb`, change the helper so it passes `deposit_gross_cents:`:

```ruby
  def call(requested = nil, invoice: 120_000, paid: 0, deposit: 120_000, allocated: 0)
    described_class.call(invoice_amount_cents: invoice, invoice_paid_cents: paid,
                         deposit_gross_cents: deposit, deposit_allocated_cents: allocated, requested_cents: requested)
  end
```

Append to `spec/models/invoice_matcher_spec.rb` (inside the `describe`):

```ruby
  it "matches on the deposit's gross, so a fee-reduced payout matches its invoice" do
    invoice = create(:invoice, business: business, amount_cents: 100_000)
    payout = create(:transaction, account: account, amount_cents: 97_070, processor_fee_cents: 2_930)
    expect(described_class.for_businesses([ business.id ]).for(payout, business.id)).to eq([ invoice ])
  end
```

Append to the first `describe` in `spec/models/transaction_linked_deposit_spec.rb`:

```ruby
  it "counts the processor fee toward the unallocated amount" do
    deposit.update!(processor_fee_cents: 500)
    expect(deposit.unallocated_cents).to eq(500)
    expect(Transaction.linkable_deposits).to include(deposit)
    expect(deposit.update(processor_fee_cents: 0)).to be(true)
    expect(deposit.update(amount_cents: 119_000, processor_fee_cents: 999)).to be(false)
  end
```

Append inside `describe ".link"` in `spec/services/invoice_payments_spec.rb`:

```ruby
    context "with a processor fee" do
      let(:payout) { create(:transaction, account: account, amount_cents: 116_490, payee: "STRIPE", posted_on: Date.new(2026, 2, 3)) }

      it "records the fee and pays the invoice in full from the payout's gross" do
        result = described_class.link(invoice: invoice, deposit: payout, processor_fee_cents: 3_510)
        expect(result).to be_ok
        expect(result.payment.amount_cents).to eq(120_000)
        expect(payout.reload.processor_fee_cents).to eq(3_510)
        expect(invoice.reload).to be_paid
      end

      it "keeps a fee the deposit already has" do
        payout.update!(processor_fee_cents: 3_510)
        described_class.link(invoice: invoice, deposit: payout, processor_fee_cents: 99)
        expect(payout.reload.processor_fee_cents).to eq(3_510)
        expect(invoice.reload).to be_paid
      end
    end
```

Append to `spec/requests/invoice_payments_spec.rb` (inside the `describe`):

```ruby
  it "lets an untouched amount follow a fee typed on the same row" do
    sign_in_as user_with_role("editor", business)
    payout = create(:transaction, account: account, amount_cents: 116_490, payee: "STRIPE PAYOUT", posted_on: Date.current - 1)
    post business_invoice_payments_path(business, invoice),
      params: { deposit_id: payout.id, processor_fee: "35.10", amount: "1164.90", proposed_amount: "1164.90" }
    expect(invoice.reload).to be_paid
    expect(payout.reload.processor_fee_cents).to eq(3_510)
  end

  it "respects an amount the editor changed even with a fee" do
    sign_in_as user_with_role("editor", business)
    payout = create(:transaction, account: account, amount_cents: 116_490, payee: "STRIPE PAYOUT", posted_on: Date.current - 1)
    post business_invoice_payments_path(business, invoice),
      params: { deposit_id: payout.id, processor_fee: "35.10", amount: "500.00", proposed_amount: "1164.90" }
    expect(invoice.reload.paid_cents).to eq(50_000)
  end

  it "rejects a negative or unreadable fee" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, processor_fee: "-1" }
    expect(flash[:alert]).to eq("Processor fee can't be negative.")
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, processor_fee: "abc" }
    expect(flash[:alert]).to eq("Processor fee is not a valid amount.")
    expect(InvoicePayment.count).to eq(0)
  end

  it "shows a fee field for deposits without a fee" do
    sign_in_as user_with_role("editor", business)
    get new_business_invoice_payment_path(business, invoice)
    expect(response.body).to include('aria-label="Processor fee"', 'name="proposed_amount"')
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/invoices/allocation_spec.rb spec/models/invoice_matcher_spec.rb spec/models/transaction_linked_deposit_spec.rb spec/services/invoice_payments_spec.rb spec/requests/invoice_payments_spec.rb`
Expected: FAIL (unknown keyword `deposit_gross_cents`, matcher returns `[]`, unknown keyword `processor_fee_cents`).

- [ ] **Step 3: Gross-based allocation**

`app/models/transaction.rb`:

```ruby
  UNALLOCATED_SQL = "transactions.amount_cents + transactions.processor_fee_cents - COALESCE((SELECT SUM(invoice_payments.amount_cents) " \
                    "FROM invoice_payments WHERE invoice_payments.deposit_id = transactions.id), 0)".freeze
```

```ruby
  def unallocated_cents = gross_cents - allocated_cents
```

In `linked_deposit_stays_payable`, add `|| will_save_change_to_processor_fee_cents?` to `changed`, and replace `amount_cents.to_i >= allocated_cents` with `gross_cents >= allocated_cents`.

`app/models/invoices/allocation.rb`: rename the keyword `deposit_amount_cents:` to `deposit_gross_cents:` and use it in `unallocated = deposit_gross_cents - deposit_allocated_cents`.

`app/models/invoice_matcher.rb`, in `for`:

```ruby
    @index.fetch([ business_id, txn.gross_cents ], []).sort_by { [ _1.due_date, _1.id ] }.first(LIMIT)
```

- [ ] **Step 4: Fee on link**

In `app/services/invoice_payments.rb`, change `link`'s signature and body up to the allocation:

```ruby
  def self.link(invoice:, deposit:, amount_cents: nil, category: nil, processor_fee_cents: nil)
    ApplicationRecord.transaction do
      invoice.lock!
      deposit.lock!
      error = link_error(invoice, deposit)
      next failure(error) if error

      deposit.processor_fee_cents = processor_fee_cents if processor_fee_cents.to_i.positive? && deposit.processor_fee_cents.zero?
      allocation = Invoices::Allocation.call(
        invoice_amount_cents: invoice.amount_cents, invoice_paid_cents: invoice.paid_cents,
        deposit_gross_cents: deposit.gross_cents, deposit_allocated_cents: deposit.allocated_cents,
        requested_cents: amount_cents
      )
      next failure(allocation.error) unless allocation.ok?

      income = income_category_for(deposit, category)
      next failure("Choose an income category for this deposit.") unless income

      deposit.assign_attributes(category: income, categorized_by: "user") unless deposit.category_id == income.id
      next failure(deposit.errors.full_messages.to_sentence) if deposit.changed? && !deposit.save

      payment = invoice.payments.create!(deposit: deposit, amount_cents: allocation.amount_cents)
      invoice.sync_payment_status!
      Result.new(payment: payment, error: nil)
    end
  end
```

- [ ] **Step 5: Controller and form**

In `app/controllers/invoice_payments_controller.rb`, replace `link` and `requested_cents`:

```ruby
  def link(deposit)
    fee, fee_error = processor_fee_cents
    return InvoicePayments::Result.new(payment: nil, error: fee_error) if fee_error

    cents, error = requested_cents(fee)
    return InvoicePayments::Result.new(payment: nil, error: error) if error

    category_id = scalar_params(:category_id)[:category_id]
    category = category_id && @business.categories.active.income.find(category_id)
    InvoicePayments.link(invoice: @invoice, deposit: deposit, amount_cents: cents, category: category, processor_fee_cents: fee)
  end

  def processor_fee_cents
    text = scalar_params(:processor_fee)[:processor_fee]
    return [ nil, nil ] if text.nil?

    cents = Money.parse(text).cents
    cents.negative? ? [ nil, "Processor fee can't be negative." ] : [ cents, nil ]
  rescue Money::ParseError => e
    [ nil, "Processor fee #{e.message}." ]
  end

  # The amount field is prefilled before any fee is typed; left untouched, it follows the fee (spec §4.3).
  def requested_cents(fee)
    return [ nil, nil ] unless params.key?(:amount)

    text = scalar_params(:amount)[:amount]
    return [ nil, "Amount can't be blank." ] if text.nil?
    return [ nil, nil ] if fee.to_i.positive? && text == scalar_params(:proposed_amount)[:proposed_amount]

    [ Money.parse(text).cents, nil ]
  rescue Money::ParseError => e
    [ nil, "Amount #{e.message}." ]
  end
```

`app/views/invoice_payments/_deposits.html.erb`: replace the header row with

```erb
    <tr><th>Date</th><th>Account</th><th>Payee</th><th>Category</th><th class="num">Amount</th><th class="num">Fee</th><th class="num">Unallocated</th><th></th></tr>
```

and replace the cells from the amount through the form with

```erb
        <td class="num"><%= money(deposit.amount_cents) %></td>
        <td class="num"><%= deposit.processor_fee_cents.positive? ? money(deposit.processor_fee_cents) : "—" %></td>
        <td class="num"><%= money(deposit.unallocated_cents) %></td>
        <td>
          <%= form_with url: business_invoice_payments_path(business, invoice), class: "inline-form" do |f| %>
            <% proposed = Money.new([ deposit.unallocated_cents, invoice.outstanding_cents ].min).to_input %>
            <%= hidden_field_tag :deposit_id, deposit.id, id: nil %>
            <%= hidden_field_tag :proposed_amount, proposed, id: nil %>
            <%= text_field_tag :amount, proposed, id: nil, size: 10, inputmode: "decimal", aria: { label: "Amount" } %>
            <% if deposit.processor_fee_cents.zero? %>
              <%= text_field_tag :processor_fee, nil, id: nil, size: 8, inputmode: "decimal", placeholder: "Stripe fee", aria: { label: "Processor fee" } %>
            <% end %>
            <% if deposit.category_id.nil? && gross_receipts.size != 1 %>
              <%= select_tag :category_id, options_from_collection_for_select(income_categories, :id, :name), id: nil, aria: { label: "Income category" } %>
            <% end %>
            <%= f.submit "Link" %>
          <% end %>
        </td>
```

- [ ] **Step 6: Run the specs**

Run the Step 2 command → PASS. Then `bundle exec rspec` (inbox hint and invoice payment system specs must stay green) and `bin/rubocop`.

- [ ] **Step 7: Commit**

```bash
git add app spec
git commit -m "Sales tax: invoice allocation on gross, processor fee on Record payment

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Invoice sales tax and per-payment tax shares

**Files:**
- Create: `app/models/invoices/tax_share.rb`, `spec/models/invoices/tax_share_spec.rb`
- Modify: `app/models/invoice.rb`, `app/services/invoice_payments.rb`, `app/controllers/invoices_controller.rb`, `app/views/invoices/_form.html.erb`, `app/views/invoices/show.html.erb`, `app/views/invoices/_payments.html.erb`, `spec/models/invoice_spec.rb`, `spec/services/invoice_payments_spec.rb`, `spec/requests/invoices_spec.rb`

**Interfaces:**
- Consumes: `invoices.sales_tax_cents` and `invoice_payments.sales_tax_cents` (Task 5); `Category#taxable?` and `Category.taxable_gross_receipts` (Task 1); `Business#collects_sales_tax?` (Task 4).
- Produces:
  - `Invoices::TaxShare.call(invoice_amount_cents:, invoice_tax_cents:, paid_before_cents:, shares_before_cents:, payment_cents:)` → Integer.
  - `money_attribute :sales_tax` on `Invoice`.
  - `InvoicePayments::TAXED_INVOICE_MESSAGE`.
  - Each new `InvoicePayment` stores `sales_tax_cents`.

- [ ] **Step 1: Write the failing specs**

`spec/models/invoices/tax_share_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Invoices::TaxShare do
  def call(payment, paid_before: 0, shares_before: 0, amount: 10_000, tax: 1_000)
    described_class.call(invoice_amount_cents: amount, invoice_tax_cents: tax, paid_before_cents: paid_before,
                         shares_before_cents: shares_before, payment_cents: payment)
  end

  it "gives a full payment the whole tax" do
    expect(call(10_000)).to eq(1_000)
  end

  it "pro-rates partial payments and lets the last one absorb rounding" do
    expect(call(3_333)).to eq(333)
    expect(call(3_333, paid_before: 3_333, shares_before: 333)).to eq(333)
    expect(call(3_334, paid_before: 6_666, shares_before: 666)).to eq(334)
  end

  it "is zero for an untaxed invoice" do
    expect(call(5_000, tax: 0)).to eq(0)
  end
end
```

Append to `spec/models/invoice_spec.rb` (inside the top-level `describe`):

```ruby
  describe "sales tax" do
    let(:business) { create(:business) }

    before { create(:sales_tax_profile, business: business) }

    it "is part of the amount and must be below it" do
      expect(build(:invoice, business: business, amount_cents: 109_250, sales_tax: "92.50")).to be_valid
      expect(build(:invoice, business: business, amount_cents: 10_000, sales_tax_cents: 10_000)).not_to be_valid
      expect(build(:invoice, business: business, sales_tax: "-1")).not_to be_valid
      expect(build(:invoice, business: business, sales_tax: "").tap(&:valid?).sales_tax_cents).to eq(0)
    end

    it "needs an active sales tax profile" do
      invoice = build(:invoice, sales_tax_cents: 100)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:sales_tax]).to include("needs an active sales tax profile")
    end

    it "can't change once payments are linked" do
      invoice = create(:invoice, business: business, amount_cents: 109_250, sales_tax_cents: 9_250)
      create(:invoice_payment, invoice: invoice, amount_cents: 10_000)
      expect(invoice.reload.update(sales_tax_cents: 0)).to be(false)
      expect(invoice.errors[:base]).to include("Unlink payments before changing sales tax.")
    end
  end
```

Append to `spec/services/invoice_payments_spec.rb` (top level, after the existing `describe ".link"` block, still inside `RSpec.describe InvoicePayments`):

```ruby
  describe "invoice sales tax" do
    let!(:profile) { create(:sales_tax_profile, business: business) }
    let!(:consulting) { create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt") }
    let(:taxed) { create(:invoice, business: business, amount_cents: 109_250, sales_tax_cents: 9_250) }

    it "stores the payment's share and leaves the deposit's direct tax alone" do
      check = create(:transaction, account: account, amount_cents: 109_250, payee: "RIVERSIDE CHECK")
      result = described_class.link(invoice: taxed, deposit: check)
      expect(result.payment.sales_tax_cents).to eq(9_250)
      expect(check.reload.sales_tax_cents).to eq(0)
      expect(check.total_sales_tax_cents).to eq(9_250)
      expect(check.category).to eq(sales)
    end

    it "keeps a batched payout's direct tax and invoice share apart, and unlink removes only the share" do
      invoice = create(:invoice, business: business, amount_cents: 54_625, sales_tax_cents: 4_625)
      payout = create(:transaction, account: account, amount_cents: 82_000, processor_fee_cents: 2_625, payee: "STRIPE",
                                    category: sales, sales_tax_cents: 2_540)
      result = described_class.link(invoice: invoice, deposit: payout, amount_cents: 54_625)
      expect(result.payment.sales_tax_cents).to eq(4_625)
      expect(payout.reload.total_sales_tax_cents).to eq(7_165)
      described_class.unlink(result.payment)
      expect(payout.reload.total_sales_tax_cents).to eq(2_540)
      expect(payout.sales_tax_cents).to eq(2_540)
    end

    it "makes the final partial payment's share absorb rounding" do
      first = create(:transaction, account: account, amount_cents: 33_333, payee: "PART ONE")
      second = create(:transaction, account: account, amount_cents: 75_917, payee: "PART TWO")
      one = described_class.link(invoice: taxed, deposit: first).payment
      two = described_class.link(invoice: taxed, deposit: second).payment
      expect(one.sales_tax_cents).to eq(2_822)
      expect(one.sales_tax_cents + two.sales_tax_cents).to eq(9_250)
    end

    it "rejects an exempt deposit for a taxed invoice" do
      deposit.update!(category: consulting)
      result = described_class.link(invoice: taxed, deposit: deposit)
      expect(result.error).to eq("This invoice includes sales tax — categorize the deposit as a taxable sale.")
      requested = create(:transaction, account: account, amount_cents: 109_250)
      expect(described_class.link(invoice: taxed, deposit: requested, category: consulting).error)
        .to eq("This invoice includes sales tax — categorize the deposit as a taxable sale.")
    end

    it "picks the single taxable gross-receipts category even when an exempt one is also on line 1" do
      check = create(:transaction, account: account, amount_cents: 109_250)
      expect(described_class.link(invoice: taxed, deposit: check)).to be_ok
      expect(check.reload.category).to eq(sales)
    end

    it "refuses a share that would push the deposit's tax to its gross" do
      invoice = create(:invoice, business: business, amount_cents: 10_000, sales_tax_cents: 9_000)
      payout = create(:transaction, account: account, amount_cents: 10_000, category: sales, sales_tax_cents: 1_500)
      result = described_class.link(invoice: invoice, deposit: payout)
      expect(result.error).to eq("Sales tax on this deposit would reach its gross amount — lower its direct sales tax first.")
      expect(InvoicePayment.count).to eq(0)
    end
  end
```

Append to `spec/requests/invoices_spec.rb` (inside the top-level `describe`; it already has `let!(:business)` and `let!(:client)`):

```ruby
  it "shows and saves sales tax only when the business collects it" do
    editor = user_with_role("editor", business)
    sign_in_as editor
    get new_business_invoice_path(business)
    expect(response.body).not_to include("invoice[sales_tax]")
    create(:sales_tax_profile, business: business)
    get new_business_invoice_path(business)
    expect(response.body).to include("invoice[sales_tax]")
    post business_invoices_path(business), params: { invoice: { client_id: client.id, number: "T-1", issue_date: "2026-03-01",
                                                                due_date: "2026-03-31", amount: "1092.50", sales_tax: "92.50" } }
    expect(business.invoices.find_by!(number: "T-1").sales_tax_cents).to eq(9_250)
  end
```


- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/invoices/tax_share_spec.rb spec/models/invoice_spec.rb spec/services/invoice_payments_spec.rb spec/requests/invoices_spec.rb`
Expected: FAIL (`uninitialized constant Invoices::TaxShare`, `unknown attribute 'sales_tax'`).

- [ ] **Step 3: TaxShare**

`app/models/invoices/tax_share.rb`:

```ruby
module Invoices
  # One payment's share of an invoice's sales tax, rounded once; the completing payment absorbs rounding.
  module TaxShare
    def self.call(invoice_amount_cents:, invoice_tax_cents:, paid_before_cents:, shares_before_cents:, payment_cents:)
      return 0 if invoice_tax_cents.zero?
      return invoice_tax_cents - shares_before_cents if paid_before_cents + payment_cents == invoice_amount_cents

      Money.round_rational(Rational(payment_cents * invoice_tax_cents, invoice_amount_cents))
    end
  end
end
```

- [ ] **Step 4: Invoice model**

In `app/models/invoice.rb`, add `money_attribute :sales_tax, allow_blank: true` under `money_attribute :amount`, `before_validation { self.sales_tax_cents ||= 0 }` after the validations, and `validate :sales_tax_valid`. Private method:

```ruby
  def sales_tax_valid
    tax = sales_tax_cents.to_i
    if tax.negative? then errors.add(:sales_tax, "can't be negative")
    elsif amount_cents && tax.positive? && tax >= amount_cents then errors.add(:sales_tax, "must be less than the invoice amount")
    elsif tax.positive? && will_save_change_to_sales_tax_cents? && !business&.collects_sales_tax?
      errors.add(:sales_tax, "needs an active sales tax profile")
    end
    return unless persisted? && will_save_change_to_sales_tax_cents? && payments.exists?

    errors.add(:base, "Unlink payments before changing sales tax.")
  end
```

- [ ] **Step 5: Shares in `InvoicePayments.link`**

In `app/services/invoice_payments.rb`:

1. Constant at the top of the class:

```ruby
  TAXED_INVOICE_MESSAGE = "This invoice includes sales tax — categorize the deposit as a taxable sale.".freeze
```

2. Replace everything in `link` from `income = income_category_for(...)` down through the `create!` line with:

```ruby
      income = income_category_for(deposit, category, invoice)
      unless income
        next failure(invoice.sales_tax_cents.positive? && category ? TAXED_INVOICE_MESSAGE : "Choose an income category for this deposit.")
      end

      share = Invoices::TaxShare.call(
        invoice_amount_cents: invoice.amount_cents, invoice_tax_cents: invoice.sales_tax_cents, paid_before_cents: invoice.paid_cents,
        shares_before_cents: invoice.payments.sum(:sales_tax_cents), payment_cents: allocation.amount_cents
      )
      if share.positive? && deposit.total_sales_tax_cents + share >= deposit.gross_cents
        next failure("Sales tax on this deposit would reach its gross amount — lower its direct sales tax first.")
      end

      deposit.assign_attributes(category: income, categorized_by: "user") unless deposit.category_id == income.id
      next failure(deposit.errors.full_messages.to_sentence) if deposit.changed? && !deposit.save

      payment = invoice.payments.create!(deposit: deposit, amount_cents: allocation.amount_cents, sales_tax_cents: share)
```

3. In `link_error`, before the final `elsif invoice.payments.exists?...` branch, add:

```ruby
    elsif invoice.sales_tax_cents.positive? && deposit.category && !deposit.category.taxable? then TAXED_INVOICE_MESSAGE
```

4. Replace `income_category_for`:

```ruby
  def self.income_category_for(deposit, requested, invoice)
    return deposit.category if deposit.category

    taxed = invoice.sales_tax_cents.positive?
    if requested
      allowed = deposit.business.categories.active.income.exists?(requested.id) && (!taxed || requested.taxable?)
      return allowed ? requested : nil
    end

    candidates = taxed ? deposit.business.categories.taxable_gross_receipts.order(:name).to_a : gross_receipts_categories(deposit.business)
    candidates.first if candidates.one?
  end
```

- [ ] **Step 6: Screens**

- `app/controllers/invoices_controller.rb`: `PERMITTED = %i[number issue_date due_date amount sales_tax description pdf].freeze`.
- `app/views/invoices/_form.html.erb`, after the amount line:

```erb
  <% if @business.collects_sales_tax? %>
    <p><%= f.label :sales_tax, "Sales tax (included in amount)" %> <%= f.text_field :sales_tax, inputmode: "decimal" %></p>
  <% end %>
```

- `app/views/invoices/show.html.erb`, after the Amount `dt/dd`:

```erb
  <% if @invoice.sales_tax_cents.positive? %>
    <dt>Sales tax</dt><dd><%= money(@invoice.sales_tax_cents) %> (included)</dd>
  <% end %>
```

- `app/views/invoices/_payments.html.erb`: add `<th class="num">Sales tax</th>` after the Amount header and `<td class="num"><%= money(payment.sales_tax_cents) %></td>` after the amount cell.

- [ ] **Step 7: Run the specs**

Run the Step 2 command → PASS. Then `bundle exec rspec` and `bin/rubocop`.

- [ ] **Step 8: Commit**

```bash
git add app spec
git commit -m "Sales tax: invoice sales tax with per-payment shares

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Reports count income net of tax and gross of fees

**Files:**
- Modify: `app/models/reports/category_totals.rb`, `app/models/reports/transaction_csv.rb`, `app/controllers/transaction_exports_controller.rb`, `app/controllers/household_transaction_exports_controller.rb`, `spec/models/reports/loaders_spec.rb`, `spec/models/reports/csv_spec.rb`

**Interfaces:**
- Consumes: `Transaction::INVOICE_TAX_SQL`, `#net_income_cents`, `#total_sales_tax_cents` (Task 5); `Category#processor_fees` (Task 1).
- Produces: `Reports::CategoryTotals.load(business_ids:, range:)` (same signature):
  - income totals are net income;
  - the business's `processor_fees` category gets −(sum of fees on categorized income deposits);
  - remittance totals are dropped.
  
  `Reports::TransactionCsv::HEADERS` gains "Processor fee", "Sales tax", "Net income" at the end.

- [ ] **Step 1: Write the failing specs**

Append inside `describe Reports::CategoryTotals` in `spec/models/reports/loaders_spec.rb`:

```ruby
    context "with sales tax and processor fees" do
      let!(:profile) { create(:sales_tax_profile, business: business) }
      let(:sales) { create(:category, :income, business: business, name: "Sales") }
      let!(:fees) { create(:category, business: business, name: "Merchant fees", schedule_c_line: "10", processor_fees: true) }

      before do
        create(:transaction, account: account, category: sales, amount_cents: 97_070, processor_fee_cents: 2_930, sales_tax_cents: 8_241,
                             posted_on: Date.new(2026, 3, 6))
      end

      def totals = Reports::CategoryTotals.load(business_ids: [ business.id ], range: year).to_h { [ _1.name, _1.sum_cents ] }

      it "nets out sales tax and adds the fee back to income, showing the fee as an expense" do
        expect(totals).to eq("Sales" => 91_759, "Merchant fees" => -2_930)
      end

      it "merges fees with real transactions in the fee category" do
        create(:transaction, account: account, category: fees, amount_cents: -1_500, posted_on: Date.new(2026, 3, 7))
        expect(totals["Merchant fees"]).to eq(-4_430)
      end

      it "nets out invoice tax shares" do
        invoice = create(:invoice, business: business, amount_cents: 54_625, sales_tax_cents: 4_625)
        create(:invoice_payment, invoice: invoice, amount_cents: 54_625, sales_tax_cents: 4_625,
                                 deposit: create(:transaction, account: account, category: sales, amount_cents: 54_625, posted_on: Date.new(2026, 3, 8)))
        expect(totals["Sales"]).to eq(91_759 + 50_000)
      end

      it "leaves remittances out of income and expense" do
        remittance = business.categories.sales_tax_remittance.sole
        create(:transaction, account: account, category: remittance, amount_cents: -8_241, posted_on: Date.new(2026, 4, 15))
        expect(totals.keys).to contain_exactly("Sales", "Merchant fees")
      end

      it "agrees on the P&L, Schedule C, and the household P&L" do
        loaded = Reports::CategoryTotals.load(business_ids: [ business.id ], range: year)
        pnl = Reports::ProfitAndLoss.new(category_totals: loaded, mileage_deduction_cents: 0)
        expect(pnl.net_profit_cents).to eq(91_759 - 2_930)
        lines = Reports::ScheduleCSummary.new(category_totals: loaded, mileage_deduction_cents: 0).lines
        expect(lines.slice("1", "10")).to eq("1" => 91_759, "10" => 2_930)
        household = Reports::HouseholdProfitAndLoss.new({ business => pnl })
        expect(household.column(:net_profit_cents)[:total]).to eq(pnl.net_profit_cents)
      end
    end
```

In `spec/models/reports/csv_spec.rb`, change the expected row in "writes one row per transaction with deductible amounts" to end with the three new columns:

```ruby
      expect(rows.second).to eq([ "2026-02-01", "Pat Consulting", "Checking", "'=cmd", nil, "-33.33", "Meals", "24b", "no", "16.67", "0.00", "0.00", nil ])
```

and add inside `describe Reports::TransactionCsv`:

```ruby
    it "writes the fee, the total sales tax, and net income for income" do
      create(:sales_tax_profile, business: business)
      sales = create(:category, :income, business: business, name: "Sales")
      create(:transaction, account: account, category: sales, payee: "STRIPE", amount_cents: 97_070, processor_fee_cents: 2_930,
                           sales_tax_cents: 8_467, posted_on: Date.new(2026, 2, 2))
      row = CSV.parse(Reports::TransactionCsv.generate(Transaction.includes(:category, :invoice_payments, account: :business)), headers: true)
        .find { _1["Payee"] == "STRIPE" }
      expect(row.to_h.slice("Processor fee", "Sales tax", "Net income", "Deductible amount"))
        .to eq("Processor fee" => "29.30", "Sales tax" => "84.67", "Net income" => "915.33", "Deductible amount" => "915.33")
    end
```

(`business` ("Pat Consulting") and `account` ("Checking") are the `let`s at the top of `csv_spec.rb`.)

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/reports/loaders_spec.rb spec/models/reports/csv_spec.rb`
Expected: FAIL (Sales shows 97_070; no Merchant fees total; CSV row has 10 columns).

- [ ] **Step 3: CategoryTotals**

Replace `app/models/reports/category_totals.rb`:

```ruby
module Reports
  module CategoryTotals
    COLUMNS = %w[accounts.business_id categories.id categories.name categories.kind categories.schedule_c_line categories.deductible_bps].freeze
    # Income is net of collected sales tax and gross of processor fees (sales tax spec §6).
    NET_SQL = "CASE WHEN categories.kind = 'income' THEN transactions.amount_cents + transactions.processor_fee_cents " \
              "- transactions.sales_tax_cents - #{Transaction::INVOICE_TAX_SQL} ELSE transactions.amount_cents END".freeze

    def self.load(business_ids:, range:)
      scope = Transaction.countable.for_businesses(business_ids).where(posted_on: range).joins(:category)
      totals = scope.where(categories: { kind: %w[income expense] }).group(*COLUMNS).sum(Arel.sql(NET_SQL))
        .map do |(business_id, category_id, name, kind, line, bps), sum|
          CategoryTotal.new(business_id:, category_id:, name:, kind:, schedule_c_line: line, deductible_bps: bps, sum_cents: sum)
        end
      fees = scope.where(categories: { kind: "income" }).group("accounts.business_id").sum("transactions.processor_fee_cents")
      with_fees(totals, fees.select { |_, cents| cents.positive? })
    end

    def self.with_fees(totals, fees_by_business)
      return totals if fees_by_business.empty?

      Category.where(business_id: fees_by_business.keys, processor_fees: true).each do |category|
        fee = fees_by_business.fetch(category.business_id)
        index = totals.index { _1.category_id == category.id }
        if index
          totals[index] = totals[index].with(sum_cents: totals[index].sum_cents - fee)
        else
          totals << CategoryTotal.new(business_id: category.business_id, category_id: category.id, name: category.name, kind: category.kind,
                                      schedule_c_line: category.schedule_c_line, deductible_bps: category.deductible_bps, sum_cents: -fee)
        end
      end
      totals
    end
    private_class_method :with_fees
  end
end
```

- [ ] **Step 4: Transaction CSV and exports**

`app/models/reports/transaction_csv.rb`:

```ruby
    HEADERS = [ "Date", "Business", "Account", "Payee", "Memo", "Amount", "Category", "Schedule C line", "Transfer", "Deductible amount",
                "Processor fee", "Sales tax", "Net income" ].freeze
```

In the row loop, change the income branch of `deductible` to `elsif category&.income? && category.schedule_c_line then txn.net_income_cents`, and append to the row array:

```ruby
            Money.new(txn.processor_fee_cents).to_input, Money.new(txn.total_sales_tax_cents).to_input,
            category&.income? ? Money.new(txn.net_income_cents).to_input : nil
```

In both `TransactionExportsController#show` and `HouseholdTransactionExportsController#show`, change `.includes(:category, account: :business)` to `.includes(:category, :invoice_payments, account: :business)`.

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/models/reports spec/requests/reports_spec.rb` → PASS. Then `bundle exec rspec`, `bin/rubocop`, and `bin/brakeman --no-pager` (no new warnings).

- [ ] **Step 6: Commit**

```bash
git add app spec
git commit -m "Sales tax: reports count income net of tax and gross of fees

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Remittances, sales tax entries, period reports

**Files:**
- Create: `app/models/sales_tax.rb`, `app/models/sales_tax/entries.rb`, `app/models/sales_tax/remittance_period.rb`, `spec/models/sales_tax/entries_spec.rb`, `spec/models/sales_tax/remittance_period_spec.rb`
- Modify: `app/models/transaction.rb`, `app/models/sales_tax_profile.rb`, `spec/models/sales_tax_profile_spec.rb`

**Interfaces:**
- Consumes: `SalesTax::PeriodReport` (Task 3), `SalesTaxProfile#calendar` (Task 4), transaction amounts (Task 5).
- Produces:
  - `SalesTax::Entries.for(business, range)` → `Result(deposits:, remittances:)`. Deposits are by `posted_on` in range, taxable/exempt only. Remittances are by `sales_tax_period_starts_on` in range.
  - `SalesTax.reports_for(business, today: Date.current)` → `Array<PeriodReport>`, oldest first (`[]` without a profile).
  - `SalesTax.report_for(business, period, today: Date.current)` → `PeriodReport`.
  - `SalesTax.build_reports(business, periods, today)` → `Array<PeriodReport>`.
  - `SalesTax::RemittancePeriod.default_for(business, posted_on, today: Date.current)` → `Date` or nil.
  - A transaction in a remittance category gets a default `sales_tax_period_starts_on`; leaving the category clears it; the value must be a period start.

- [ ] **Step 1: Write the failing specs**

`spec/models/sales_tax/entries_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SalesTax::Entries do
  let(:business) { create(:business) }
  let!(:profile) { create(:sales_tax_profile, business: business) }
  let(:account) { create(:account, business: business) }
  let(:sales) { create(:category, :income, business: business, name: "Sales") }
  let(:consulting) { create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt") }
  let(:interest) { create(:category, business: business, name: "Interest", kind: "income", schedule_c_line: "6") }
  let(:remittance) { business.categories.sales_tax_remittance.sole }
  let(:q2) { Date.new(2026, 4, 1)..Date.new(2026, 6, 30) }

  it "loads taxable and exempt deposits in range with gross and total tax" do
    taxed = create(:transaction, account: account, category: sales, amount_cents: 97_070, processor_fee_cents: 2_930,
                                 sales_tax_cents: 8_467, posted_on: Date.new(2026, 4, 1))
    create(:transaction, account: account, category: consulting, amount_cents: 50_000, posted_on: Date.new(2026, 6, 30))
    create(:transaction, account: account, category: interest, amount_cents: 300, posted_on: Date.new(2026, 5, 1))
    create(:transaction, account: account, category: sales, amount_cents: 1_000, posted_on: Date.new(2026, 7, 1))
    create(:transaction, account: account, category: sales, amount_cents: 1_000, posted_on: Date.new(2026, 5, 1), excluded: true)
    create(:transaction, account: account, amount_cents: 1_000, posted_on: Date.new(2026, 5, 1))
    invoice = create(:invoice, business: business, amount_cents: 10_925, sales_tax_cents: 925)
    create(:invoice_payment, invoice: invoice, amount_cents: 10_925, sales_tax_cents: 925,
                             deposit: create(:transaction, account: account, category: sales, amount_cents: 10_925, posted_on: Date.new(2026, 5, 2)))

    deposits = described_class.for(business, q2).deposits
    expect(deposits.map { [ _1.treatment, _1.gross_cents, _1.total_tax_cents ] })
      .to eq([ [ "taxable", 100_000, 8_467 ], [ "taxable", 10_925, 925 ], [ "exempt", 50_000, 0 ] ])
    expect(deposits.first.source).to eq(taxed)
  end

  it "loads remittances by the period they pay, not the date they were paid" do
    create(:transaction, account: account, category: remittance, amount_cents: -8_000, posted_on: Date.new(2026, 7, 15),
                         sales_tax_period_starts_on: Date.new(2026, 4, 1))
    remittances = described_class.for(business, q2).remittances
    expect(remittances.map { [ _1.amount_cents, _1.period_starts_on ] }).to eq([ [ -8_000, Date.new(2026, 4, 1) ] ])
  end

  it "feeds whole-calendar period reports" do
    create(:transaction, account: account, category: sales, amount_cents: 10_925, sales_tax_cents: 925, posted_on: Date.new(2026, 2, 3))
    reports = SalesTax.reports_for(business, today: Date.new(2026, 5, 1))
    expect(reports.map { [ _1.period.label, _1.tax_collected_cents, _1.status ] }).to eq([ [ "Q1 2026", 925, "overdue" ], [ "Q2 2026", 0, "open" ] ])
    expect(SalesTax.reports_for(create(:business))).to eq([])
  end
end
```

`spec/models/sales_tax/remittance_period_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SalesTax::RemittancePeriod do
  let(:business) { create(:business) }
  let!(:profile) { create(:sales_tax_profile, business: business) }
  let(:account) { create(:account, business: business) }
  let(:sales) { create(:category, :income, business: business, name: "Sales") }
  let(:remittance) { business.categories.sales_tax_remittance.sole }

  def taxed_sale(on) = create(:transaction, account: account, category: sales, amount_cents: 10_925, sales_tax_cents: 925, posted_on: on)

  it "defaults to the oldest ended period with a balance owed" do
    taxed_sale(Date.new(2026, 2, 1))
    taxed_sale(Date.new(2026, 5, 1))
    expect(described_class.default_for(business, Date.new(2026, 7, 10), today: Date.new(2026, 7, 10))).to eq(Date.new(2026, 1, 1))
  end

  it "falls back to the most recent ended period, then the current one" do
    expect(described_class.default_for(business, Date.new(2026, 7, 10), today: Date.new(2026, 7, 10))).to eq(Date.new(2026, 4, 1))
    expect(described_class.default_for(business, Date.new(2026, 2, 10), today: Date.new(2026, 2, 10))).to eq(Date.new(2026, 1, 1))
  end

  it "is nil without a profile" do
    expect(described_class.default_for(create(:business), Date.new(2026, 7, 10))).to be_nil
  end

  describe "on transactions" do
    it "assigns the default when a rule or a person categorizes a remittance, and clears it when it leaves" do
      taxed_sale(Date.new(2026, 2, 1))
      payment = create(:transaction, account: account, payee: "TN DEPT OF REVENUE", amount_cents: -925, posted_on: Date.new(2026, 4, 15))
      rule = create(:rule, business: business, value: "TN DEPT", category: remittance)
      RuleApplier.new(business).apply([ payment ])
      expect(payment.reload.sales_tax_period_starts_on).to eq(Date.new(2026, 1, 1))
      payment.update!(category: create(:category, business: business), rule: nil)
      expect(payment.sales_tax_period_starts_on).to be_nil
      expect(rule).to be_persisted
    end

    it "keeps a chosen period and rejects one that isn't a period start" do
      payment = create(:transaction, account: account, category: remittance, amount_cents: -925, posted_on: Date.new(2026, 7, 15),
                                     sales_tax_period_starts_on: Date.new(2026, 4, 1))
      expect(payment.sales_tax_period_starts_on).to eq(Date.new(2026, 4, 1))
      expect(payment.update(sales_tax_period_starts_on: Date.new(2026, 4, 2))).to be(false)
      expect(payment.errors[:sales_tax_period_starts_on]).to include("isn't a filing period for this business")
    end
  end
end
```

Append to `spec/models/sales_tax_profile_spec.rb` (inside the `describe`):

```ruby
  it "locks the calendar once a remittance points at a period" do
    profile = create(:sales_tax_profile, business: business)
    create(:transaction, account: create(:account, business: business), category: business.categories.sales_tax_remittance.sole,
                         amount_cents: -100, posted_on: Date.new(2026, 4, 15), sales_tax_period_starts_on: Date.new(2026, 1, 1))
    expect(profile.reload.update(filing_frequency: "monthly")).to be(false)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/sales_tax spec/models/sales_tax_profile_spec.rb`
Expected: FAIL (`uninitialized constant SalesTax::Entries`).

- [ ] **Step 3: Entries and the module**

`app/models/sales_tax/entries.rb`:

```ruby
module SalesTax
  # The only place that turns transactions into sales tax report inputs (spec §5.3).
  module Entries
    Result = Data.define(:deposits, :remittances)

    def self.for(business, range)
      scope = Transaction.countable.for_businesses(business.id).joins(:category)
      deposits = scope.where(posted_on: range, categories: { kind: "income", sales_tax_treatment: %w[taxable exempt] })
        .includes(:account, :category, :invoice_payments).order(:posted_on, :id)
        .map do |txn|
          PeriodReport::Deposit.new(posted_on: txn.posted_on, treatment: txn.category.sales_tax_treatment, gross_cents: txn.gross_cents,
                                    total_tax_cents: txn.total_sales_tax_cents, source: txn)
        end
      remittances = scope.where(categories: { kind: "sales_tax_remittance" }, sales_tax_period_starts_on: range)
        .includes(:account).order(:posted_on, :id)
        .map do |txn|
          PeriodReport::Remittance.new(posted_on: txn.posted_on, amount_cents: txn.amount_cents,
                                       period_starts_on: txn.sales_tax_period_starts_on, source: txn)
        end
      Result.new(deposits: deposits, remittances: remittances)
    end
  end
end
```

`app/models/sales_tax.rb`:

```ruby
module SalesTax
  def self.reports_for(business, today: Date.current)
    profile = business.sales_tax_profile
    return [] unless profile

    build_reports(business, profile.calendar(today: today).periods, today)
  end

  def self.report_for(business, period, today: Date.current) = build_reports(business, [ period ], today).first

  def self.build_reports(business, periods, today)
    return [] if periods.empty?

    entries = Entries.for(business, periods.first.starts_on..periods.last.ends_on)
    filings = business.sales_tax_filings.index_by(&:period_starts_on)
    periods.map do |period|
      PeriodReport.new(period: period, deposits: entries.deposits, remittances: entries.remittances,
                       filing: filings[period.starts_on], today: today)
    end
  end
end
```

`app/models/sales_tax/remittance_period.rb`:

```ruby
module SalesTax
  # Which period a new remittance pays by default (spec §4.4).
  module RemittancePeriod
    def self.default_for(business, posted_on, today: Date.current)
      profile = business.sales_tax_profile
      return unless profile && posted_on

      calendar = profile.calendar(today: [ posted_on, today ].max)
      ended = calendar.periods.select { _1.ends_on < posted_on }
      owed = SalesTax.build_reports(business, ended, today).find { _1.balance_cents.positive? }
      (owed&.period || ended.last || calendar.period_for(posted_on))&.starts_on
    end
  end
end
```

- [ ] **Step 4: Transaction callbacks**

In `app/models/transaction.rb`, after `before_validation :default_sales_amounts`, add `before_validation :assign_remittance_period`, and add `validate :remittance_period_in_calendar` after `validate :sales_tax_allowed`. Private methods:

```ruby
  def assign_remittance_period
    if category&.sales_tax_remittance?
      self.sales_tax_period_starts_on ||= SalesTax::RemittancePeriod.default_for(account.business, posted_on) if account
    else
      self.sales_tax_period_starts_on = nil
    end
  end

  def remittance_period_in_calendar
    return if sales_tax_period_starts_on.nil?

    calendar = account&.business&.sales_tax_profile&.calendar
    errors.add(:sales_tax_period_starts_on, "isn't a filing period for this business") unless calendar&.include_start?(sales_tax_period_starts_on)
  end
```

(`clear_category_for_transfer` runs first, so a transfer has no category and its period is cleared.)

- [ ] **Step 5: Lock the calendar on remittances too**

In `app/models/sales_tax_profile.rb`:

```ruby
  def calendar_in_use?
    business.sales_tax_filings.exists? || Transaction.for_businesses(business_id).where.not(sales_tax_period_starts_on: nil).exists?
  end
```

- [ ] **Step 6: Run the specs**

Run: `bundle exec rspec spec/models/sales_tax spec/models/sales_tax_profile_spec.rb spec/services/rule_applier_spec.rb` → PASS. Then `bundle exec rspec` and `bin/rubocop`.

- [ ] **Step 7: Commit**

```bash
git add app spec
git commit -m "Sales tax: remittance periods, entries, and period reports

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Sales tax page (profile and period list), category treatment form, nav

**Files:**
- Create: `app/controllers/sales_tax_profiles_controller.rb`, `app/views/sales_tax_profiles/show.html.erb`, `app/helpers/sales_tax_helper.rb`, `spec/requests/sales_tax_profiles_spec.rb`
- Modify: `config/routes.rb`, `app/views/businesses/_nav.html.erb`, `app/controllers/categories_controller.rb`, `app/views/categories/_form.html.erb`, `app/views/categories/index.html.erb`, `spec/requests/categories_spec.rb`

**Interfaces:**
- Consumes: `SalesTax.reports_for` (Task 9), `SalesTaxProfile` (Task 4).
- Produces:
  - Routes:
    - `business_sales_tax_profile_path(business)` (GET show, PATCH update)
    - `business_sales_tax_period_path(business, starts_on)` (GET; controller in Task 11)
    - `business_sales_tax_period_filing_path(business, starts_on)` (POST, DELETE; Task 11)
  - Helpers:
    - `sales_tax_status_badge(report)`
    - `sales_tax_due_label(period)` ("Oct 20, 2026")
    - `sales_tax_period_options(business)` → `[[label, iso_date], …]`, newest first

- [ ] **Step 1: Write the failing specs**

`spec/requests/sales_tax_profiles_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Sales tax page" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let(:owner) { user_with_role("owner", business) }
  let(:params) { { sales_tax_profile: { tn_account_number: "1002003004", filing_frequency: "quarterly", default_rate_percent: "9.25",
                                        starts_on: "2026-01-01", active: "1" } } }

  it "is 404 for non-members and on the personal book" do
    sign_in_as create(:user)
    get business_sales_tax_profile_path(business)
    expect(response).to have_http_status(:not_found)

    household_owner = create(:user, :household_owner)
    book = PersonalBookProvisioner.call(Household.first)
    sign_in_as household_owner
    get business_sales_tax_profile_path(book)
    expect(response).to have_http_status(:not_found)
  end

  it "tells viewers and editors when it isn't set up, and forbids them from setting it up" do
    %w[viewer editor].each do |role|
      sign_in_as user_with_role(role, business)
      get business_sales_tax_profile_path(business)
      expect(response.body).to include("Sales tax isn't set up for this business.")
      patch business_sales_tax_profile_path(business), params: params
      expect(response).to have_http_status(:forbidden)
    end
  end

  it "lets the owner set it up, which creates the remittance category, and lists the periods" do
    sign_in_as owner
    get business_sales_tax_profile_path(business)
    expect(response.body).to include("Default rate (%)")
    patch business_sales_tax_profile_path(business), params: params
    expect(response).to redirect_to(business_sales_tax_profile_path(business))
    expect(business.reload).to be_collects_sales_tax
    expect(business.sales_tax_profile.default_rate_bps).to eq(925)
    expect(business.categories.sales_tax_remittance).to exist
    follow_redirect!
    expect(response.body).to include("Q1 2026", "Apr 20, 2026")
  end

  [ "9.255", "0", "20.01", "abc", "" ].each do |rate|
    it "rejects a rate of #{rate.inspect} without a 500" do
      create(:sales_tax_profile, business: business)
      sign_in_as owner
      patch business_sales_tax_profile_path(business), params: { sales_tax_profile: params[:sales_tax_profile].merge(default_rate_percent: rate) }
      expect(response).to have_http_status(:unprocessable_content)
      expect(business.sales_tax_profile.reload.default_rate_bps).to eq(925)
    end
  end

  it "shows viewers the periods once set up, and hides them while inactive" do
    create(:sales_tax_profile, business: business)
    viewer = user_with_role("viewer", business)
    sign_in_as viewer
    get business_sales_tax_profile_path(business)
    expect(response.body).to include("Q1 2026")
    expect(response.body).not_to include("Default rate (%)")
    business.sales_tax_profile.update!(active: false)
    get business_sales_tax_profile_path(business)
    expect(response.body).to include("Sales tax isn't set up for this business.")
  end

  it "shows Sales tax in the nav to owners always and to others once it is set up" do
    sign_in_as user_with_role("viewer", business)
    get business_path(business)
    expect(response.body).not_to include(">Sales tax<")
    create(:sales_tax_profile, business: business)
    get business_path(business)
    expect(response.body).to include(">Sales tax<")
  end
end
```

Append to `spec/requests/categories_spec.rb` (inside the top-level `describe`; the example builds its own business):

```ruby
  it "offers sales tax treatment and the remittance kind only when the business collects sales tax" do
    business = create(:business)
    sign_in_as user_with_role("editor", business)
    get new_business_category_path(business)
    expect(response.body).not_to include("Sales tax treatment")
    create(:sales_tax_profile, business: business)
    get new_business_category_path(business)
    expect(response.body).to include("Sales tax treatment", "sales_tax_remittance")
    post business_categories_path(business), params: { category: { name: "Consulting", kind: "income", schedule_c_line: "1", sales_tax_treatment: "exempt" } }
    expect(business.categories.find_by!(name: "Consulting").sales_tax_treatment).to eq("exempt")
    get business_categories_path(business)
    expect(response.body).to include("Exempt sales")
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/requests/sales_tax_profiles_spec.rb spec/requests/categories_spec.rb`
Expected: FAIL (`undefined method 'business_sales_tax_profile_path'`).

- [ ] **Step 3: Routes**

In `config/routes.rb`, inside `resources :businesses ... do`, after the `resource :tithe` line:

```ruby
    resource :sales_tax_profile, only: %i[show update], path: "sales_tax"
    resources :sales_tax_periods, only: :show, param: :starts_on, path: "sales_tax/periods" do
      resource :filing, only: %i[create destroy], controller: "sales_tax_filings"
    end
```

- [ ] **Step 4: Helper, controller, view**

`app/helpers/sales_tax_helper.rb`:

```ruby
module SalesTaxHelper
  def sales_tax_status_badge(report)
    tag.span(report.status.humanize, class: "badge badge-#{report.status}")
  end

  def sales_tax_due_label(period)
    period.due_on.strftime("%b %-d, %Y")
  end

  def sales_tax_period_options(business)
    profile = business.sales_tax_profile
    return [] unless profile

    profile.calendar.periods.reverse.map { [ _1.label, _1.starts_on.iso8601 ] }
  end
end
```

`app/controllers/sales_tax_profiles_controller.rb`:

```ruby
class SalesTaxProfilesController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly

  PERMITTED = %i[tn_account_number filing_frequency default_rate_percent starts_on active].freeze

  before_action :require_owner!, only: :update

  def show
    @collects = @business.collects_sales_tax?
    @reports = @collects ? SalesTax.reports_for(@business).reverse : []
    @profile = @business.sales_tax_profile
    @profile ||= SalesTaxProfile.new(business: @business, filing_frequency: "quarterly", default_rate_bps: 925,
                                     starts_on: Date.current.beginning_of_quarter, active: true) if current_membership.owner?
  end

  def update
    @profile = @business.sales_tax_profile || SalesTaxProfile.new(business: @business)
    @profile.assign_attributes(params.expect(sales_tax_profile: PERMITTED))
    if @profile.save
      redirect_to business_sales_tax_profile_path(@business), notice: "Sales tax settings saved."
    else
      @collects = false
      @reports = []
      render :show, status: :unprocessable_content
    end
  end
end
```

`app/views/sales_tax_profiles/show.html.erb`:

```erb
<%= business_nav @business %>
<h1>Sales tax</h1>
<% if current_membership.owner? %>
  <%= form_with model: @profile, url: business_sales_tax_profile_path(@business), method: :patch do |f| %>
    <%= render "shared/errors", record: @profile %>
    <p><%= f.label :tn_account_number, "TN account number" %> <%= f.text_field :tn_account_number %></p>
    <p><%= f.label :filing_frequency, "Filing frequency" %> <%= f.select :filing_frequency, SalesTaxProfile::FREQUENCIES.map { [ _1.humanize, _1 ] } %></p>
    <p><%= f.label :default_rate_percent, "Default rate (%)" %> <%= f.text_field :default_rate_percent, size: 6 %> <small>state 7% plus local</small></p>
    <p><%= f.label :starts_on, "Collecting since" %> <%= f.date_field :starts_on %></p>
    <p><%= f.check_box :active %> <%= f.label :active %></p>
    <%= f.submit "Save" %>
  <% end %>
<% end %>
<%# @collects is read before the owner's blank form builds an unsaved profile, which would otherwise look active %>
<% if @collects %>
  <table>
    <thead><tr><th>Period</th><th>Due</th><th class="num">Collected</th><th class="num">Remitted</th><th class="num">Balance</th><th>Status</th></tr></thead>
    <tbody>
      <% @reports.each do |report| %>
        <tr>
          <td><%= link_to report.period.label, business_sales_tax_period_path(@business, report.period.starts_on) %></td>
          <td><%= sales_tax_due_label(report.period) %></td>
          <td class="num"><%= money(report.tax_collected_cents) %></td>
          <td class="num"><%= money(report.remitted_cents) %></td>
          <td class="num"><%= money(report.balance_cents) %></td>
          <td><%= sales_tax_status_badge(report) %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% elsif !current_membership.owner? %>
  <p>Sales tax isn't set up for this business.</p>
<% end %>
```

- [ ] **Step 5: Nav**

In `app/views/businesses/_nav.html.erb`, inside the `unless business.personal?` block after the Aging item:

```erb
      <% if current_membership&.owner? || business.collects_sales_tax? %>
        <li><%= link_to "Sales tax", business_sales_tax_profile_path(business) %></li>
      <% end %>
```

- [ ] **Step 6: Category form and list**

- `app/controllers/categories_controller.rb`: `PERMITTED = %i[name kind schedule_c_line deductible_percent tithable tithe sales_tax_treatment].freeze`.
- `app/views/categories/_form.html.erb`: replace the kind line with

```erb
  <% kinds = [ [ "Income", "income" ], [ "Expense", "expense" ] ] %>
  <% kinds << [ "Sales tax remittance", "sales_tax_remittance" ] if @business.collects_sales_tax? || category.sales_tax_remittance? %>
  <p><%= f.label :kind %> <%= f.select :kind, kinds %></p>
```

and, inside the `else` (business) branch after the deductible line:

```erb
    <% if @business.collects_sales_tax? %>
      <p>
        <%= f.label :sales_tax_treatment, "Sales tax treatment" %>
        <%= f.select :sales_tax_treatment, Category::SALES_TAX_TREATMENT_LABELS.invert, include_blank: "Default" %>
        <small>income categories only</small>
      </p>
    <% end %>
```

- `app/views/categories/index.html.erb`: for business books with `@business.collects_sales_tax?`, add a `<th>Sales tax</th>` header and a `<td><%= Category::SALES_TAX_TREATMENT_LABELS[category.sales_tax_treatment] %></td>` cell after the Deductible column. Also show `ScheduleC.label` only when `category.schedule_c_line` is present (remittance rows have none):

```erb
          <td><%= category.schedule_c_line ? ScheduleC.label(category.schedule_c_line) : "—" %></td>
```

- [ ] **Step 7: Run the specs**

Run: `bundle exec rspec spec/requests/sales_tax_profiles_spec.rb spec/requests/categories_spec.rb` → PASS. Then `bundle exec rspec` and `bin/rubocop`.

- [ ] **Step 8: Commit**

```bash
git add config app spec
git commit -m "Sales tax: settings page with period list, category treatment, nav

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Period page, filings, CSV

**Files:**
- Create: `app/controllers/concerns/sales_tax_period_lookup.rb`, `app/controllers/sales_tax_periods_controller.rb`, `app/controllers/sales_tax_filings_controller.rb`, `app/views/sales_tax_periods/show.html.erb`, `app/models/reports/sales_tax_period_csv.rb`, `spec/requests/sales_tax_periods_spec.rb`, `spec/models/reports/sales_tax_period_csv_spec.rb`

**Interfaces:**
- Consumes: routes and helpers (Task 10), `SalesTax.report_for` (Task 9), `SalesTaxFiling` (Task 4).
- Produces:
  - `SalesTaxPeriodLookup#find_sales_tax_period(param)` → `SalesTax::Calendar::Period`; raises `ActiveRecord::RecordNotFound`.
  - `Reports::SalesTaxPeriodCsv.generate(report)` → String.

- [ ] **Step 1: Write the failing specs**

`spec/requests/sales_tax_periods_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Sales tax periods" do
  let!(:business) { create(:business) }
  let!(:profile) { create(:sales_tax_profile, business: business) }
  let(:account) { create(:account, business: business, name: "Checking") }
  let(:sales) { create(:category, :income, business: business, name: "Sales") }
  let(:q1) { Date.new(2026, 1, 1) }

  before do
    create(:transaction, account: account, category: sales, payee: "STRIPE PAYOUT", amount_cents: 97_070, processor_fee_cents: 2_930,
                         sales_tax_cents: 8_467, posted_on: Date.new(2026, 2, 6))
    create(:transaction, account: account, category: business.categories.sales_tax_remittance.sole, payee: "=TN DOR",
                         amount_cents: -8_467, posted_on: Date.new(2026, 4, 10), sales_tax_period_starts_on: q1)
  end

  it "shows the period's figures, deposits, and remittances to viewers, with a CSV" do
    sign_in_as user_with_role("viewer", business)
    get business_sales_tax_period_path(business, q1)
    expect(response.body).to include("Q1 2026", "$1,000.00", "$84.67", "STRIPE PAYOUT")
    expect(response.body).not_to include("Mark filed")
    get business_sales_tax_period_path(business, q1, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("'=TN DOR")
  end

  it "lets editors file and unfile, and forbids viewers" do
    sign_in_as user_with_role("viewer", business)
    post business_sales_tax_period_filing_path(business, q1), params: { sales_tax_filing: { filed_on: "2026-04-10" } }
    expect(response).to have_http_status(:forbidden)

    sign_in_as user_with_role("editor", business)
    post business_sales_tax_period_filing_path(business, q1), params: { sales_tax_filing: { filed_on: "2026-04-10", confirmation_number: "TN123" } }
    expect(response).to redirect_to(business_sales_tax_period_path(business, q1))
    follow_redirect!
    expect(response.body).to include("Paid", "TN123")
    post business_sales_tax_period_filing_path(business, q1), params: { sales_tax_filing: { filed_on: "2026-04-10" } }
    expect(flash[:alert]).to include("is already filed")
    delete business_sales_tax_period_filing_path(business, q1)
    expect(business.sales_tax_filings).to be_empty
  end

  it "rejects a blank filing date with a flash" do
    sign_in_as user_with_role("editor", business)
    post business_sales_tax_period_filing_path(business, q1), params: { sales_tax_filing: { filed_on: "" } }
    expect(flash[:alert]).to include("Filed on can't be blank")
  end

  [ "2026-01-02", "abc", "2025-10-01", "2030-01-01" ].each do |starts_on|
    it "is 404 for the period #{starts_on}" do
      sign_in_as user_with_role("owner", business)
      get business_sales_tax_period_path(business, starts_on)
      expect(response).to have_http_status(:not_found)
      post business_sales_tax_period_filing_path(business, starts_on), params: { sales_tax_filing: { filed_on: "2026-04-10" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  it "is 404 while the profile is inactive and for non-members" do
    profile.update!(active: false)
    sign_in_as user_with_role("owner", business)
    get business_sales_tax_period_path(business, q1)
    expect(response).to have_http_status(:not_found)
    profile.update!(active: true)
    sign_in_as create(:user)
    get business_sales_tax_period_path(business, q1)
    expect(response).to have_http_status(:not_found)
  end
end
```

`spec/models/reports/sales_tax_period_csv_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Reports::SalesTaxPeriodCsv do
  it "writes deposits, remittances, and the summary" do
    business = create(:business)
    create(:sales_tax_profile, business: business)
    account = create(:account, business: business, name: "Checking")
    sales = create(:category, :income, business: business)
    create(:transaction, account: account, category: sales, payee: "STRIPE", amount_cents: 97_070, processor_fee_cents: 2_930,
                         sales_tax_cents: 8_467, posted_on: Date.new(2026, 2, 6))
    period = business.sales_tax_profile.calendar(today: Date.new(2026, 5, 1)).periods.first
    rows = CSV.parse(described_class.generate(SalesTax.report_for(business, period, today: Date.new(2026, 5, 1))))
    expect(rows.first).to eq(described_class::HEADERS)
    expect(rows.second).to eq([ "2026-02-06", "Taxable sale", "Checking", "STRIPE", "1000.00", "29.30", "84.67", "0.00", nil ])
    expect(rows).to include([ "Tax collected", "84.67" ], [ "Balance owed", "84.67" ], [ "Status", "overdue" ])
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/requests/sales_tax_periods_spec.rb spec/models/reports/sales_tax_period_csv_spec.rb`
Expected: FAIL (`uninitialized constant SalesTaxPeriodsController`).

- [ ] **Step 3: Lookup concern and controllers**

`app/controllers/concerns/sales_tax_period_lookup.rb`:

```ruby
# Resolves a period from its start date through the business's calendar; anything else is 404.
module SalesTaxPeriodLookup
  private

  def find_sales_tax_period(param)
    raise ActiveRecord::RecordNotFound unless @business.collects_sales_tax?

    starts_on = Date.iso8601(param.to_s)
    @business.sales_tax_profile.calendar.periods.find { _1.starts_on == starts_on } || raise(ActiveRecord::RecordNotFound)
  rescue Date::Error
    raise ActiveRecord::RecordNotFound
  end
end
```

`app/controllers/sales_tax_periods_controller.rb`:

```ruby
class SalesTaxPeriodsController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly
  include SalesTaxPeriodLookup

  def show
    @report = SalesTax.report_for(@business, find_sales_tax_period(params[:starts_on]))
    respond_to do |format|
      format.html
      format.csv do
        send_data Reports::SalesTaxPeriodCsv.generate(@report),
          filename: "#{@business.name.parameterize}-sales-tax-#{@report.period.starts_on}.csv", type: "text/csv"
      end
    end
  end
end
```

`app/controllers/sales_tax_filings_controller.rb`:

```ruby
class SalesTaxFilingsController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly
  include SalesTaxPeriodLookup

  before_action :require_editor!
  before_action :set_period

  def create
    filing = @business.sales_tax_filings.new(params.expect(sales_tax_filing: %i[filed_on confirmation_number]))
    filing.period_starts_on = @period.starts_on
    if filing.save
      redirect_to period_path, notice: "Period marked filed."
    else
      redirect_to period_path, alert: filing.errors.full_messages.to_sentence
    end
  end

  def destroy
    @business.sales_tax_filings.find_by!(period_starts_on: @period.starts_on).destroy!
    redirect_to period_path, notice: "Filing removed.", status: :see_other
  end

  private

  def set_period
    @period = find_sales_tax_period(params[:sales_tax_period_starts_on])
  end

  def period_path = business_sales_tax_period_path(@business, @period.starts_on)
end
```

- [ ] **Step 4: CSV**

`app/models/reports/sales_tax_period_csv.rb`:

```ruby
require "csv"

module Reports
  module SalesTaxPeriodCsv
    HEADERS = [ "Date", "Type", "Account", "Payee", "Gross", "Processor fee", "Sales tax (direct)", "Sales tax (invoices)", "Remitted" ].freeze

    def self.generate(report)
      CSV.generate do |csv|
        csv << HEADERS
        report.deposits.each do |deposit|
          txn = deposit.source
          csv << [ deposit.posted_on.iso8601, deposit.treatment == "taxable" ? "Taxable sale" : "Exempt sale", CsvSafe.text(txn.account.name),
                   CsvSafe.text(txn.payee), cents(deposit.gross_cents), cents(txn.processor_fee_cents), cents(txn.sales_tax_cents),
                   cents(txn.invoice_tax_cents), nil ]
        end
        report.remittances.each do |remittance|
          txn = remittance.source
          csv << [ remittance.posted_on.iso8601, "Remittance", CsvSafe.text(txn.account.name), CsvSafe.text(txn.payee),
                   nil, nil, nil, nil, cents(-remittance.amount_cents) ]
        end
        csv << []
        csv << [ "Gross sales", cents(report.gross_sales_cents) ]
        csv << [ "Exempt sales", cents(report.exempt_sales_cents) ]
        csv << [ "Taxable sales", cents(report.taxable_sales_cents) ]
        csv << [ "Tax collected", cents(report.tax_collected_cents) ]
        csv << [ "Remitted", cents(report.remitted_cents) ]
        csv << [ "Balance owed", cents(report.balance_cents) ]
        csv << [ "Status", report.status ]
      end
    end

    def self.cents(value) = Money.new(value).to_input
    private_class_method :cents
  end
end
```

- [ ] **Step 5: View**

`app/views/sales_tax_periods/show.html.erb`:

```erb
<%= business_nav @business %>
<% period = @report.period %>
<h1>Sales tax · <%= period.label %> <%= sales_tax_status_badge(@report) %></h1>
<p><%= period.starts_on %> – <%= period.ends_on %> · due <%= sales_tax_due_label(period) %></p>
<%# dt and dd on separate lines so page text reads "Tax collected $84.67" %>
<dl class="details">
  <dt>Gross sales</dt>
  <dd><%= money(@report.gross_sales_cents) %></dd>
  <dt>Exempt sales</dt>
  <dd><%= money(@report.exempt_sales_cents) %></dd>
  <dt>Taxable sales</dt>
  <dd><%= money(@report.taxable_sales_cents) %></dd>
  <dt>Tax collected</dt>
  <dd><%= money(@report.tax_collected_cents) %></dd>
  <dt>Remitted</dt>
  <dd><%= money(@report.remitted_cents) %></dd>
  <dt>Balance owed</dt>
  <dd><%= money(@report.balance_cents) %></dd>
</dl>

<% if @report.filing %>
  <p>Filed <%= @report.filing.filed_on %><%= " · confirmation #{@report.filing.confirmation_number}" if @report.filing.confirmation_number.present? %></p>
  <%= button_to "Unfile", business_sales_tax_period_filing_path(@business, period.starts_on), method: :delete if current_membership.can_edit? %>
<% elsif current_membership.can_edit? %>
  <%= form_with scope: :sales_tax_filing, url: business_sales_tax_period_filing_path(@business, period.starts_on), class: "inline-form" do |f| %>
    <%= f.label :filed_on, "Filed on" %> <%= f.date_field :filed_on, value: Date.current %>
    <%= f.label :confirmation_number, "Confirmation number" %> <%= f.text_field :confirmation_number %>
    <%= f.submit "Mark filed" %>
  <% end %>
<% end %>

<h2>Sales</h2>
<table>
  <thead><tr><th>Date</th><th>Account</th><th>Payee</th><th>Type</th><th class="num">Gross</th><th class="num">Fee</th><th class="num">Direct tax</th><th class="num">Invoice tax</th></tr></thead>
  <tbody>
    <% @report.deposits.each do |deposit| %>
      <% txn = deposit.source %>
      <tr>
        <td><%= deposit.posted_on %></td>
        <td><%= txn.account.name %></td>
        <td><%= txn.payee %></td>
        <td><%= deposit.treatment == "taxable" ? "Taxable" : "Exempt" %></td>
        <td class="num"><%= money(deposit.gross_cents) %></td>
        <td class="num"><%= money(txn.processor_fee_cents) %></td>
        <td class="num"><%= money(txn.sales_tax_cents) %></td>
        <td class="num"><%= money(txn.invoice_tax_cents) %></td>
      </tr>
    <% end %>
  </tbody>
</table>

<h2>Remittances</h2>
<% if @report.remittances.any? %>
  <table>
    <thead><tr><th>Date</th><th>Account</th><th>Payee</th><th class="num">Remitted</th></tr></thead>
    <tbody>
      <% @report.remittances.each do |remittance| %>
        <tr><td><%= remittance.posted_on %></td><td><%= remittance.source.account.name %></td><td><%= remittance.source.payee %></td>
            <td class="num"><%= money(-remittance.amount_cents) %></td></tr>
      <% end %>
    </tbody>
  </table>
<% else %>
  <p>No remittances for this period yet.</p>
<% end %>
<p><%= link_to "Download CSV", business_sales_tax_period_path(@business, period.starts_on, format: :csv) %> · <%= link_to "All periods", business_sales_tax_profile_path(@business) %></p>
```

- [ ] **Step 6: Run the specs**

Run the Step 2 command → PASS. Then `bundle exec rspec`, `bin/rubocop`, and `bin/brakeman --no-pager`.

- [ ] **Step 7: Commit**

```bash
git add app spec
git commit -m "Sales tax: period page, filings, CSV

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Transaction form fee and tax, tax-inclusive button, remittance period, "needs tax" filter

**Files:**
- Modify: `app/controllers/transactions_controller.rb`, `app/views/transactions/_form.html.erb`, `app/views/transactions/index.html.erb`, `app/models/transaction.rb`, `app/models/transaction_filter.rb`, `app/helpers/categories_helper.rb`, `app/views/rules/_form.html.erb`, `app/views/inboxes/_row.html.erb`, `spec/requests/transactions_spec.rb`, `spec/requests/inbox_spec.rb`, `spec/models/transaction_filter_spec.rb`

**Interfaces:**
- Consumes: `SalesTax::InclusiveTax` (Task 3), transaction amounts and guards (Task 5), `sales_tax_period_options` (Task 10).
- Spec deviation: spec §4.2 also describes a Stimulus controller that previews the tax-inclusive value in the browser. This plan drops the preview. The button is a plain submit (`apply_inclusive_tax=1`), the server computes the value (the spec already requires that the client value is never trusted), and the form comes back with the value and a notice. No JavaScript is needed, and rack_test can drive it.
- Produces:
  - `Transaction.needing_sales_tax` scope.
  - `TransactionFilter` status `"needs_tax"`.
  - `CategoriesHelper#category_groups(categories)` → `[[label, [Category…]], …]` for Income, Expense, Sales tax (empty groups dropped).
  - Transaction params `processor_fee`, `sales_tax`, `sales_tax_period_starts_on`, and the `apply_inclusive_tax=1` submit.

- [ ] **Step 1: Write the failing specs**

Append to `spec/requests/transactions_spec.rb` (inside the top-level `describe`):

```ruby
  describe "sales tax fields" do
    let!(:business) { create(:business) }
    let!(:profile) { create(:sales_tax_profile, business: business) }
    let!(:sales) { create(:category, :income, business: business, name: "Sales") }
    let!(:consulting) { create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt") }
    let(:account) { create(:account, :csv, business: business) }
    let!(:payout) { create(:transaction, account: account, payee: "STRIPE PAYOUT", amount_cents: 97_070, external_id: "x1") }

    before { sign_in_as user_with_role("editor", business) }

    it "saves a fee and tax on an imported deposit" do
      patch business_transaction_path(business, payout),
        params: { transaction: { category_id: sales.id, processor_fee: "29.30", sales_tax: "84.67" } }
      expect([ payout.reload.processor_fee_cents, payout.sales_tax_cents ]).to eq([ 2_930, 8_467 ])
    end

    it "computes tax-inclusive tax on the unallocated gross and returns to the form" do
      patch business_transaction_path(business, payout),
        params: { apply_inclusive_tax: "1", transaction: { category_id: sales.id, processor_fee: "29.30", sales_tax: "" } }
      expect(response).to redirect_to(edit_business_transaction_path(business, payout))
      expect(flash[:notice]).to eq("Sales tax set to $84.67 (tax-inclusive at 9.25%).")
      expect(payout.reload.sales_tax_cents).to eq(8_467)
    end

    [ [ "-5", "can't be negative" ], [ "abc", "is not a valid amount" ], [ "1,00", "is not a valid amount" ] ].each do |input, message|
      it "rejects a fee of #{input.inspect}" do
        patch business_transaction_path(business, payout), params: { transaction: { category_id: sales.id, processor_fee: input } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Processor fee #{message}")
      end
    end

    it "refuses tax on an exempt deposit" do
      patch business_transaction_path(business, payout), params: { transaction: { category_id: consulting.id, sales_tax: "5.00" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Clear the sales tax first.")
    end

    it "gives a manual remittance the default period and lets the editor pick another" do
      cash = create(:account, business: business, name: "Cash")
      remittance = business.categories.sales_tax_remittance.sole
      post business_transactions_path(business), params: { transaction: { account_id: cash.id, posted_on: "2026-04-10", payee: "TN DOR",
                                                                            amount: "84.67", direction: "out", category_id: remittance.id } }
      created = cash.transactions.sole
      expect(created.sales_tax_period_starts_on).to eq(Date.new(2026, 1, 1))
      patch business_transaction_path(business, created), params: { transaction: { sales_tax_period_starts_on: "2026-04-01" } }
      expect(created.reload.sales_tax_period_starts_on).to eq(Date.new(2026, 4, 1))
    end

    it "lists taxable deposits that still need tax" do
      payout.update!(category: sales)
      create(:transaction, account: account, payee: "STRIPE DONE", amount_cents: 10_925, category: sales, sales_tax_cents: 925)
      get business_transactions_path(business, status: "needs_tax")
      expect(response.body).to include("STRIPE PAYOUT")
      expect(response.body).not_to include("STRIPE DONE")
    end

    it "hides the fee field on the personal book" do
      household_owner = create(:user, :household_owner)
      book = PersonalBookProvisioner.call(Household.first)
      txn = create(:transaction, account: create(:account, business: book), amount_cents: 5_000)
      sign_in_as household_owner
      get edit_business_transaction_path(book, txn)
      expect(response.body).not_to include("Processor fee")
    end
  end
```

Append to `spec/requests/inbox_spec.rb` (inside the top-level `describe`):

```ruby
  it "refuses to reclassify a taxed deposit through the inbox endpoint" do
    business = create(:business)
    create(:sales_tax_profile, business: business)
    sales = create(:category, :income, business: business, name: "Sales")
    exempt = create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt")
    taxed = create(:transaction, account: create(:account, business: business), amount_cents: 10_925, category: sales, sales_tax_cents: 925)
    sign_in_as user_with_role("editor", business)
    [ { outcome: "transfer" }, { outcome: "exclude" }, { outcome: "categorize", category_id: exempt.id } ].each do |params|
      patch business_transaction_classification_path(business, taxed), params: params
      expect(flash[:alert]).to include("Clear the sales tax first.")
    end
    expect([ taxed.reload.transfer, taxed.excluded, taxed.category_id ]).to eq([ false, false, sales.id ])
  end

  it "offers the remittance category in the inbox picker" do
    business = create(:business)
    create(:sales_tax_profile, business: business)
    create(:transaction, account: create(:account, business: business), payee: "TN DOR", amount_cents: -100)
    sign_in_as user_with_role("editor", business)
    get business_inbox_path(business)
    expect(response.body).to include('label="Sales tax"', "Sales tax remittance")
  end
```

Append to `spec/models/transaction_filter_spec.rb` (inside the `describe`):

```ruby
  it "filters taxable deposits with no direct tax and no invoice links" do
    business = create(:business)
    create(:sales_tax_profile, business: business)
    account = create(:account, business: business)
    sales = create(:category, :income, business: business)
    missing = create(:transaction, account: account, amount_cents: 5_000, category: sales)
    create(:transaction, account: account, amount_cents: 5_000, category: sales, sales_tax_cents: 400)
    create(:invoice_payment, invoice: create(:invoice, business: business, amount_cents: 5_000), amount_cents: 5_000,
                             deposit: create(:transaction, account: account, amount_cents: 5_000, category: sales))
    expect(TransactionFilter.new(Transaction.for_businesses(business.id), status: "needs_tax").results).to eq([ missing ])
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/requests/transactions_spec.rb spec/requests/inbox_spec.rb spec/models/transaction_filter_spec.rb`
Expected: FAIL (unpermitted params ignored; no `needing_sales_tax`; no "Sales tax" optgroup).

- [ ] **Step 3: Scope and filter**

In `app/models/transaction.rb`, add after `scope :with_unallocated`:

```ruby
  scope :needing_sales_tax, -> {
    countable.joins(:category).where(categories: { kind: "income", sales_tax_treatment: "taxable" })
      .where(sales_tax_cents: 0).where.not(id: InvoicePayment.select(:deposit_id))
  }
```

In `app/models/transaction_filter.rb`, after the inbox line: `relation = relation.needing_sales_tax if @params[:status] == "needs_tax"`.

In `app/views/transactions/index.html.erb`, replace the status select with:

```erb
  <% statuses = [ [ "All", "" ], [ "Inbox only", "inbox" ] ] %>
  <% statuses << [ "Needs sales tax", "needs_tax" ] if @business.collects_sales_tax? %>
  <%= f.select :status, statuses, selected: params[:status] %>
```

- [ ] **Step 4: Category groups**

In `app/helpers/categories_helper.rb`:

```ruby
  def category_groups(categories)
    { "Income" => categories.select(&:income?), "Expense" => categories.select(&:expense?),
      "Sales tax" => categories.select(&:sales_tax_remittance?) }.reject { |_, list| list.empty? }.to_a
  end
```

- `app/views/rules/_form.html.erb`: replace the `grouped_collection_select` source array with `category_groups(@business.categories.active.order(:name))`.
- `app/views/inboxes/_row.html.erb`: replace the `grouped_options_for_select({...})` argument with

```erb
        <%= f.select :category_id, grouped_options_for_select(category_groups(categories).map { |label, list| [ label, list.map { [ _1.name, _1.id ] } ] }), include_blank: "Category…" %>
```

- [ ] **Step 5: Controller**

In `app/controllers/transactions_controller.rb`:

```ruby
  SALES_TAX_EDITABLE = %i[processor_fee sales_tax sales_tax_period_starts_on].freeze
```

In `create`: `attrs = params.expect(transaction: [ :account_id, *MANUAL_EDITABLE, *SALES_TAX_EDITABLE ])`. After building `@transaction`, call `apply_inclusive_tax`. On success, redirect with `redirect_after_save("Transaction added.")`.

In `update`: `permitted = (@transaction.account.manual? ? MANUAL_EDITABLE : IMPORTED_EDITABLE) + SALES_TAX_EDITABLE`. Call `apply_inclusive_tax` after `assign_attributes`. On success, `redirect_after_save("Transaction updated.")`.

Private methods:

```ruby
  def apply_inclusive_tax
    return unless params[:apply_inclusive_tax] == "1" && @business.collects_sales_tax?

    cents = SalesTax::InclusiveTax.call(gross_cents: @transaction.unallocated_cents, rate_bps: @business.sales_tax_profile.default_rate_bps)
    @transaction.sales_tax = Money.new(cents).to_input
    @inclusive_tax_cents = cents
  end

  def redirect_after_save(notice)
    if @inclusive_tax_cents
      rate = @business.sales_tax_profile.default_rate_percent
      redirect_to edit_business_transaction_path(@business, @transaction),
        notice: "Sales tax set to #{Money.new(@inclusive_tax_cents)} (tax-inclusive at #{rate}%)."
    else
      redirect_to business_transactions_path(@business), notice: notice
    end
  end
```

- [ ] **Step 6: Form**

In `app/views/transactions/_form.html.erb`, replace the category paragraph with:

```erb
  <% categories = @business.categories.active.or(@business.categories.where(id: transaction.category_id)).order(:name) %>
  <p>
    <%= f.label :category_id %>
    <%= f.grouped_collection_select :category_id, category_groups(categories), :last, :first, :id, :name, include_blank: "Uncategorized" %>
  </p>
  <% if @business.business? %>
    <p><%= f.label :processor_fee, "Processor fee" %> <%= f.text_field :processor_fee, size: 10, inputmode: "decimal" %> <small>card processor's fee on a deposit</small></p>
  <% end %>
  <% if @business.collects_sales_tax? %>
    <p>
      <%= f.label :sales_tax, "Sales tax" %> <%= f.text_field :sales_tax, size: 10, inputmode: "decimal" %>
      <%= button_tag "Tax-inclusive at default rate (#{@business.sales_tax_profile.default_rate_percent}%)",
            type: "submit", name: "apply_inclusive_tax", value: "1" %>
      <% if transaction.persisted? && transaction.invoice_tax_cents.positive? %>
        <small>plus <%= money(transaction.invoice_tax_cents) %> from linked invoices</small>
      <% end %>
    </p>
    <p>
      <%= f.label :sales_tax_period_starts_on, "Sales tax period (remittances)" %>
      <%= f.select :sales_tax_period_starts_on, sales_tax_period_options(@business),
            { include_blank: "Default", selected: transaction.sales_tax_period_starts_on&.iso8601 } %>
    </p>
  <% end %>
```

- [ ] **Step 7: Run the specs**

Run the Step 2 command → PASS. Then `bundle exec rspec` (inbox, rules, and transaction system specs must stay green), `bin/rubocop`, and `bin/brakeman --no-pager`.

- [ ] **Step 8: Commit**

```bash
git add app spec
git commit -m "Sales tax: fee and tax on the transaction form, tax-inclusive, needs-tax filter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Dashboard due card and overdue banner

**Files:**
- Create: `app/views/sales_tax/_summary.html.erb`, `app/views/sales_tax/_overdue_banner.html.erb`, `spec/requests/sales_tax_dashboard_spec.rb`
- Modify: `app/models/sales_tax.rb`, `app/controllers/dashboards_controller.rb`, `app/views/dashboards/show.html.erb`, `app/controllers/businesses_controller.rb`, `app/views/businesses/show.html.erb`

**Interfaces:**
- Consumes: `SalesTax.reports_for` (Task 9), helpers (Task 10).
- Produces: `SalesTax.summary_for(business, today: Date.current)` → `SalesTax::Summary(next_due_on, owed_cents, overdue_reports)` or nil when the business doesn't collect sales tax.

- [ ] **Step 1: Write the failing spec**

`spec/requests/sales_tax_dashboard_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Sales tax on the dashboard" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let(:account) { create(:account, business: business) }

  it "shows the next due date and owed balance, and warns about overdue periods" do
    travel_to Date.new(2026, 5, 1) do
      create(:sales_tax_profile, business: business)
      sales = create(:category, :income, business: business, name: "Sales")
      create(:transaction, account: account, category: sales, amount_cents: 10_925, sales_tax_cents: 925, posted_on: Date.new(2026, 2, 3))
      sign_in_as user_with_role("viewer", business)
      get root_path
      expect(response.body).to include("next due Jul 20", "owed $9.25")
      expect(response.body).to include("Sales tax for Pat Consulting", "Q1 2026", "isn't filed")
      get business_path(business)
      expect(response.body).to include("next due Jul 20", "isn't filed")
    end
  end

  it "shows nothing for businesses without sales tax" do
    sign_in_as user_with_role("owner", business)
    get root_path
    expect(response.body).not_to include("next due")
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/requests/sales_tax_dashboard_spec.rb`
Expected: FAIL (no "next due").

- [ ] **Step 3: Summary**

Append to `module SalesTax` in `app/models/sales_tax.rb`:

```ruby
  Summary = Data.define(:next_due_on, :owed_cents, :overdue_reports)

  def self.summary_for(business, today: Date.current)
    return unless business.collects_sales_tax?

    reports = reports_for(business, today: today)
    Summary.new(
      next_due_on: reports.reject(&:filed?).filter_map { _1.period.due_on }.select { _1 >= today }.min,
      owed_cents: reports.reject(&:paid?).sum { [ _1.balance_cents, 0 ].max },
      overdue_reports: reports.select { _1.status == "overdue" }
    )
  end
```

- [ ] **Step 4: Partials, controllers, views**

`app/views/sales_tax/_summary.html.erb`:

```erb
<% if summary %>
  <span class="sales-tax-summary"><%= link_to "Sales tax", business_sales_tax_profile_path(business) %>
    · next due <%= summary.next_due_on ? summary.next_due_on.strftime("%b %-d") : "—" %> · owed <%= money(summary.owed_cents) %></span>
<% end %>
```

`app/views/sales_tax/_overdue_banner.html.erb`:

```erb
<% summary&.overdue_reports&.each do |report| %>
  <p class="flash flash-alert">Sales tax for <%= business.name %>:
    <%= link_to report.period.label, business_sales_tax_period_path(business, report.period.starts_on) %>
    was due <%= sales_tax_due_label(report.period) %> and isn't filed.</p>
<% end %>
```

`app/controllers/dashboards_controller.rb`: change the `@businesses` line to `.includes(:sales_tax_profile)` and add:

```ruby
    @sales_tax = @businesses.index_with { SalesTax.summary_for(_1) }.compact
```

`app/views/dashboards/show.html.erb`: before `<h1>Businesses</h1>` add

```erb
<% @sales_tax.each do |business, summary| %>
  <%= render "sales_tax/overdue_banner", business: business, summary: summary %>
<% end %>
```

and inside each business `<li>`, after the receivables render: `<%= render "sales_tax/summary", business: business, summary: @sales_tax[business] %>`.

`app/controllers/businesses_controller.rb#show`: add `@sales_tax = SalesTax.summary_for(@business) if @business.business?`.

`app/views/businesses/show.html.erb`, inside the business (`else`) branch after the receivables line:

```erb
  <%= render "sales_tax/overdue_banner", business: @business, summary: @sales_tax %>
  <p><%= render "sales_tax/summary", business: @business, summary: @sales_tax %></p>
```

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/requests/sales_tax_dashboard_spec.rb spec/requests/receivables_spec.rb spec/requests/businesses_spec.rb` → PASS. Then `bundle exec rspec` and `bin/rubocop`.

- [ ] **Step 6: Commit**

```bash
git add app spec
git commit -m "Sales tax: dashboard due card and overdue banner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Demo data

**Files:**
- Modify: `lib/demo_seeder.rb`, `spec/lib/demo_seeder_spec.rb`

**Interfaces:**
- Consumes: everything above.
- Produces: "Pat Consulting" with an active quarterly profile at 9.25% starting five quarters before the current one, and:
  - "Sales" (taxable) and "Consulting" (exempt) categories;
  - weekly Stripe payouts with fees and tax, the last two left without tax;
  - three taxed invoices (paid by check, paid inside a batched payout, open);
  - every completed quarter except the latest filed and remitted.

- [ ] **Step 1: Write the failing spec**

In `spec/lib/demo_seeder_spec.rb`, change `expect(Rule.count).to eq(5)` to `expect(Rule.count).to eq(6)`, and add:

```ruby
  it "seeds a sales tax business with paid, due, and open periods" do
    run
    business = Business.find_by!(name: "Pat Consulting")
    expect(business).to be_collects_sales_tax
    reports = SalesTax.reports_for(business, today: today)
    completed = reports.select { _1.period.ends_on < today }
    expect(completed.size).to eq(5)
    expect(completed[0...-1].map(&:status)).to all(eq("paid"))
    expect(%w[due overdue]).to include(completed.last.status)
    expect(reports.last.status).to eq("open")
    expect(reports.sum(&:exempt_sales_cents)).to be > 0
    expect(business.transactions.where("processor_fee_cents > 0").count).to be > 50
    expect(InvoicePayment.where("sales_tax_cents > 0").count).to eq(2)
    expect(business.invoices.where("sales_tax_cents > 0").where(status: "sent")).to exist
    expect(Transaction.needing_sales_tax.for_businesses(business.id)).to exist
    expect(business.categories.find_by!(name: "Consulting").sales_tax_treatment).to eq("exempt")
  end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb`
Expected: FAIL (`Rule.count` 5; no profile).

- [ ] **Step 3: Seeder**

In `lib/demo_seeder.rb`, call `seed_sales_tax(consulting)` as the last line of `build` (after `seed_personal`, so the personal book's random draws are unchanged). Then add:

```ruby
  # Pat Consulting collects TN sales tax: weekly Stripe payouts (fees and tax entered), exempt consulting income,
  # taxed invoices (one by check, one inside a batched payout, one open), and every completed quarter but the latest filed and remitted.
  def seed_sales_tax(business)
    start = @today.beginning_of_quarter << 15
    business.create_sales_tax_profile!(tn_account_number: "1002003004", filing_frequency: "quarterly", default_rate_bps: 925,
                                       starts_on: start, active: true)
    bank = business.accounts.find_by!(name: "Business Checking")
    sales = business.categories.find_by!(name: "Sales")
    consulting = business.categories.create!(name: "Consulting", kind: "income", schedule_c_line: "1", sales_tax_treatment: "exempt")
    bank.transactions.where(category: sales).find_each { _1.update!(category: consulting) }
    stripe = business.rules.create!(field: "payee", operator: "contains", value: "STRIPE", outcome: "categorize", category: sales)

    sequence = 0
    payout = lambda do |date, direct, invoiced: [], tax: true|
      sequence += 1
      fee = (direct + invoiced).sum { Money.round_rational(Rational(_1 * 29, 1_000)) + 30 }
      gross = (direct + invoiced).sum
      bank.transactions.create!(posted_on: date, payee: "STRIPE PAYOUT", amount_cents: gross - fee, processor_fee_cents: fee,
                                sales_tax_cents: tax ? SalesTax::InclusiveTax.call(gross_cents: direct.sum, rate_bps: 925) : 0,
                                category: sales, categorized_by: "rule", rule: stripe, external_id: "demo-#{business.id}-stripe-#{sequence}")
    end

    friday = start + ((5 - start.wday) % 7)
    friday.step(@today, 7).each do |date|
      payout.(date, Array.new(3 + @random.rand(4)) { 2_500 + @random.rand(12_000) }, tax: date < @today - 14)
    end

    riverside = business.clients.create!(name: "Riverside Market")
    maple = business.clients.create!(name: "Maple Street Bakery")
    add_invoice = lambda do |client, cents, tax, issued|
      business.invoices.create!(client: client, number: Invoices::NumberSuggester.next(business.invoices.pluck(:number)), issue_date: issued,
                                due_date: issued + 30, amount_cents: cents, sales_tax_cents: tax, status: "sent", description: "Retail order")
    end
    link = lambda do |invoice, deposit, **options|
      result = InvoicePayments.link(invoice: invoice, deposit: deposit, **options)
      raise result.error unless result.ok?
    end

    check = bank.transactions.create!(posted_on: @today - 45, payee: "RIVERSIDE MARKET CHECK", amount_cents: 109_250,
                                      external_id: "demo-#{business.id}-riverside")
    link.(add_invoice.(riverside, 109_250, 9_250, @today - 70), check, category: sales)
    batched = add_invoice.(maple, 54_625, 4_625, @today - 30)
    link.(batched, payout.(@today - 10, [ 12_000, 18_000 ], invoiced: [ 54_625 ]), amount_cents: 54_625)
    add_invoice.(riverside, 32_775, 2_775, @today - 12)

    remittance = business.categories.sales_tax_remittance.sole
    completed = SalesTax.reports_for(business, today: @today).select { _1.period.ends_on < @today }
    completed[0...-1].each do |report|
      paid_on = report.period.due_on - 3
      bank.transactions.create!(posted_on: paid_on, payee: "TN DEPT OF REVENUE", amount_cents: -report.tax_collected_cents,
                                category: remittance, categorized_by: "user", sales_tax_period_starts_on: report.period.starts_on,
                                external_id: "demo-#{business.id}-remit-#{report.period.starts_on}")
      business.sales_tax_filings.create!(period_starts_on: report.period.starts_on, filed_on: paid_on,
                                         confirmation_number: "TN#{report.period.starts_on.strftime("%Y%m")}")
    end
  end
```

- [ ] **Step 4: Run the specs**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb` → PASS (including the 14 weekday variants). Then:

```bash
bin/rails demo:reset
bin/rails runner 'b = Business.find_by!(name: "Pat Consulting"); SalesTax.reports_for(b).each { puts [ _1.period.label, _1.status, Money.new(_1.balance_cents) ].join(" ") }'
```

Expected: five completed quarters (the first four `paid $0.00`, the fifth `due` or `overdue` with a positive balance) and the current quarter `open`.

Run `bundle exec rspec` and `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add lib spec
git commit -m "Demo: Pat Consulting collects TN sales tax with Stripe payouts, taxed invoices, filed quarters

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: End-to-end check, docs, PR

**Files:**
- Create: `spec/system/sales_tax_spec.rb`
- Modify: `README.md`, `docs/roadmap.md`

- [ ] **Step 1: Write the system spec**

`spec/system/sales_tax_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Sales tax" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, household: household, name: "Pat Consulting"), owner: owner) }

  it "records a Stripe payout's fee and tax, remits, files, and shows the period paid" do
    travel_to Date.new(2026, 4, 6) do
      system_sign_in_as owner
      visit business_sales_tax_profile_path(business)
      select "Quarterly", from: "Filing frequency"
      fill_in "Default rate (%)", with: "9.25"
      fill_in "Collecting since", with: "2026-01-01"
      click_on "Save"
      expect(page).to have_content("Sales tax settings saved.")

      visit new_business_transaction_path(business)
      fill_in "Date", with: "2026-03-13"
      fill_in "Payee", with: "STRIPE PAYOUT"
      fill_in "Amount", with: "970.70"
      choose "Money in"
      select "Sales", from: "Category"
      fill_in "Processor fee", with: "29.30"
      click_on "Tax-inclusive at default rate (9.25%)"
      expect(page).to have_content("Sales tax set to $84.67 (tax-inclusive at 9.25%).")

      visit new_business_transaction_path(business)
      fill_in "Date", with: "2026-04-06"
      fill_in "Payee", with: "TN DEPT OF REVENUE"
      fill_in "Amount", with: "84.67"
      choose "Money out"
      select "Sales tax remittance", from: "Category"
      click_on "Create Transaction"

      visit business_sales_tax_period_path(business, "2026-01-01")
      expect(page).to have_content("Tax collected $84.67")
      expect(page).to have_content("Remitted $84.67")
      fill_in "Confirmation number", with: "TN123"
      click_on "Mark filed"
      expect(page).to have_content("Period marked filed.")
      expect(page).to have_content("Paid")
    end
  end
end
```

Run: `bundle exec rspec spec/system/sales_tax_spec.rb` → PASS. (The period page puts each `dt` and `dd` on its own line (Task 11), so the page text reads "Tax collected $84.67".)

- [ ] **Step 2: README**

In `README.md`, next to the Personal book paragraph, add a short paragraph:

> **Sales tax (Tennessee).** An owner turns it on from a business's **Sales tax** page (TN account number, filing frequency, default rate, start date). Income categories are marked taxable, exempt, or not a sale. Deposits can carry the card processor's fee (Stripe) and the sales tax from the payout report, and a "tax-inclusive" button backs the tax out at the default rate. Invoices can include sales tax, which is shared out to the deposits that pay them. Each filing period shows gross, exempt, and taxable sales, tax collected, remitted, and balance owed, with its due date (the 20th of the following month, rolled past weekends and the TN holidays that can fall on it, computed for any year). Reports count income net of sales tax and gross of fees, with fees under Merchant fees.

- [ ] **Step 3: Full verification**

Run each and confirm clean output:
- `bundle exec rspec` → all examples, 0 failures, nothing else printed
- `bin/rubocop`
- `bin/brakeman --no-pager`
- `bin/bundler-audit`
- `bin/importmap audit`

- [ ] **Step 4: Rebase check against `plaid`**

`git fetch origin && git branch -r | grep plaid`. If `plaid` has already merged into `tithing`:
1. `git rebase origin/tithing` and resolve conflicts in `db/schema.rb` (re-run `bin/rails db:migrate`), `app/models/transaction.rb`, `lib/demo_seeder.rb`, `app/views/inboxes/_row.html.erb`, the dashboard, and `docs/roadmap.md`. Keep both sides' additions.
2. Re-run Step 3.

Otherwise, skip this step; the plaid branch rebases onto this one.

- [ ] **Step 5: Commit, push, open the stacked PR**

Update `docs/roadmap.md`: sub-project 4's Status → `In review (PR #N)` once the PR number is known, and its `○` → `◐` in the dependency graph.

```bash
git add spec README.md docs/roadmap.md
git commit -m "Sales tax: end-to-end spec, README, roadmap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin sales-tax
gh pr create --base tithing --title "Sales tax (Tennessee) (sub-project 4)" --body-file <body>
```

The PR body has:
- a Summary (what sales tax does, and that it's stacked on #7 and parallel with Plaid);
- the spec and plan paths;
- the **Acceptance testing** steps below;
- at the end:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

After the PR exists, amend the roadmap commit with the PR number and push again.

Acceptance testing (put the same steps in the PR body and the GB-4 Kaneo task description):

1. `bin/rails demo:reset`, `bin/dev`; log in as `pat@example.com` (password and TOTP secret printed by the reset).
2. Dashboard: Pat Consulting shows "Sales tax · next due … · owed $…". If the last completed quarter's due date has passed, a red banner says it isn't filed.
3. Pat Consulting → Sales tax: the profile form (TN account number, Quarterly, 9.25, start date, Active) and six quarters. The first four are **Paid**, the fifth **Due** or **Overdue**, and the current one **Open**.
4. Open the fifth quarter: gross, exempt, and taxable sales, tax collected, remitted $0.00, and balance owed. The Sales table lists Stripe payouts with fees and direct tax, Consulting deposits as Exempt, and the Riverside check with invoice tax. Download CSV.
5. Mark it filed with a confirmation number → status **Filed** (balance still owed). Add a manual transaction to Cash: Money out, category "Sales tax remittance", amount = the balance → back on the period page the status is **Paid**. Unfile → status returns to Due/Overdue.
6. Transactions → filter "Needs sales tax": the latest one or two STRIPE PAYOUT rows. Edit one and click "Tax-inclusive at default rate (9.25%)" → "Sales tax set to $…". The row leaves the filter.
7. On that payout, change the category to Consulting → "Clear the sales tax first." From the inbox page's classification endpoint, Transfer/Exclude on it are refused the same way.
8. Reports → P&L for the year: Sales is net of tax, and Merchant fees shows the Stripe fees. Schedule C line 1 matches Sales + Consulting, and line 10 includes Merchant fees. "Sales tax remittance" appears nowhere.
9. Invoices: open the Maple Street Bakery invoice. It shows Sales tax $46.25 (included), and its payment row shows a $46.25 share. Create a new invoice with Sales tax $10.00, then Record payment against a new manual $97.00 deposit, typing Stripe fee 3.00 and leaving the amount untouched → the invoice is **Paid**.
10. Categories → New: kind offers "Sales tax remittance", and income shows "Sales tax treatment".
11. Log in as `jordan@example.com` (viewer of Pat Consulting): Sales tax page and periods are readable, with no profile form and no Mark filed button.
12. Log in as `accountant@example.com`: the same read-only access; Jordan Design Studio → Sales tax → "Sales tax isn't set up for this business."
13. As Pat, `/businesses/<personal id>/sales_tax` → 404; the personal transaction form has no Processor fee field.

- [ ] **Step 6: Get CI green and update Kaneo**

Watch `gh pr checks --watch` and fix anything red. Then move GB-4 to In Review with a comment linking the PR, and put the acceptance steps in its description.

---

## Summary

| Task | Delivers |
|---|---|
| 1 | Category treatment, remittance kind, Merchant fees (template + backfill) |
| 2 | Pure `SalesTax::Calendar` and `SalesTax::Holidays` |
| 3 | Pure `SalesTax::InclusiveTax` and `SalesTax::PeriodReport` |
| 4 | `SalesTaxProfile` (rate %, calendar, remittance category), `SalesTaxFiling`, `Business#collects_sales_tax?` |
| 5 | Transaction fee and direct tax with all §4.1 rules and category guards |
| 6 | Gross-based invoice allocation, matcher, fee on Record payment |
| 7 | Invoice sales tax and per-payment shares |
| 8 | `Reports::CategoryTotals` net income, fee expense, remittances dropped; transaction CSV |
| 9 | Remittance period default/validation, `SalesTax::Entries`, `SalesTax.reports_for` |
| 10 | Sales tax page, profile form, period list, category treatment form, nav |
| 11 | Period page, filings, CSV, 404 rules |
| 12 | Transaction form fee/tax/tax-inclusive/period, needs-tax filter, shared category groups |
| 13 | Dashboard card and overdue banner |
| 14 | Demo data |
| 15 | System spec, README, verification, stacked PR, acceptance steps |
