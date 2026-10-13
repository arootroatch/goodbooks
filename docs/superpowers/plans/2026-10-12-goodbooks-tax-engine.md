# goodbooks Tax Engine (Sub-project 6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tell the household how much federal estimated tax to pay each quarter, when, and why: regular and annualized (Form 2210 Schedule AI) installments side by side, the lesser as "pay at least", a full worksheet, a payment log linked to the IRS debits, home office on Schedule C line 30, and per-person health insurance and retirement adjustments.

**Architecture:** Nothing derived is stored. `Tax::Inputs.load` (query) turns the household's business-kind books into plain structs, reusing `Reports::CategoryTotals`, `Reports::MileageTotals`, and `Reports::ScheduleCSummary`, so profit is already net of collected sales tax and the personal book never appears. `Tax::PeriodCalculator` (pure) computes one Schedule AI period's worksheet; `Tax::Estimator` (pure) runs it for each period up to the selected quarter and builds installments, safe harbor, and warnings into a `Tax::Estimate`. `Tax.estimate` is the one entry point controllers call.

**Tech Stack:** Ruby 4.0.7, Rails 8.1.4, SQLite, Hotwire, RSpec, FactoryBot, Capybara (rack_test), Brakeman, bundler-audit, RuboCop (rails-omakase), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-12-goodbooks-tax-engine-design.md` (parent: `docs/superpowers/specs/2026-10-05-goodbooks-design.md` §3 cross-cutting rules; sales tax: `docs/superpowers/specs/2026-10-08-goodbooks-sales-tax-design.md` §6; personal book: `docs/superpowers/specs/2026-10-06-goodbooks-tithing-design.md` §6).

## Prerequisites (before Task 1)

- `export PATH="$HOME/.rubies/ruby-4.0.7/bin:$PATH"` before every command (`ruby -v` → `ruby 4.0.7`).
- The branch `tax-engine` holds the spec and this plan. In the main checkout run `git switch main`, then `git worktree add ../goodbooks-tax-engine tax-engine` and work in `/Users/AlexRoot-Roatch/current-projects/goodbooks-tax-engine`. The PR's base is `main`.
- `bundle install`, then `bin/rails db:test:prepare`.
- `bundle exec rspec` → `N examples, 0 failures` with no other output. Record N as the baseline. If the suite isn't green, stop and report.

## Global Constraints

- Money is signed integer cents in `*_cents` columns. Display with `money(cents)`, parse input with `Money.parse` / `money_attribute`, round only through `Money.round_rational`, once per worksheet line; the rounded value is the one used downstream. Never use floats.
- Percentages are integer basis points (`9235` = 92.35%). Input and display go through `percent_attribute` (Task 1).
- Annualization factors and every rate multiplication use `Rational`.
- Schedule AI periods: Q1 Jan–Mar (×4), Q2 Jan–May (×12/5), Q3 Jan–Aug (×3/2), Q4 Jan–Dec (×1). A period whose end is after `today` uses data through `today`, factor = days in the year ÷ days elapsed (Jan 1 = day 1). A year that hasn't started has no data: profit 0, factor 1.
- Applicable percentages for the annualized installment: 22.5%, 45%, 67.5%, 90% (`2_250, 4_500, 6_750, 9_000` bps).
- Due dates: Apr 15, Jun 15, Sep 15, and Jan 15 of the next year, rolled forward a day at a time past Saturdays, Sundays, MLK Day (third Monday of January) and DC Emancipation Day observed (Apr 16; Fri Apr 15 when Apr 16 is a Saturday, Mon Apr 17 when it is a Sunday). No holiday list is maintained.
- Home office, SE health insurance, and retirement are full-year figures, applied after annualizing, never multiplied.
- Only business-kind books feed the engine (`Business.business_kind`, archived ones included). `HomeOffice` rejects the personal book.
- Never name an association, method, or local `transaction`. The estimated payment's link is `debit` (column `debit_id`), like `InvoicePayment#deposit`. `HomeOffice`'s method column is `calculation` (`method` shadows `Object#method`).
- Authorization: the taxes pages need `Current.user.can_view_household?` (else 404). Writes on tax years, payments, tax parameters, and household settings need `household_owner?` (else 403). A home office: household owner or the business's `owner` member (else 403; non-member 404; personal book 404). Adjustments: household owner or the person's own user (else 403 if the user can view the household, otherwise 404). A payment's debit is looked up through `Current.user.accessible_businesses` (else 404).
- A year in a URL must be four digits in 2000–2100, else 404 (`TaxYearParam`, Task 9). Never `Integer()` a year: `"010"` is octal.
- Strong params never list a `*_id` key. The debit id is read with `params.dig` and looked up through the accessible scope.
- `config.action_controller.raise_on_missing_callback_actions = true` in test: every `only:`/`except:` list must name existing actions.
- The IRS link always renders `target="_blank" rel="noopener noreferrer"` and uses `Household#irs_payment_url` (default `https://www.irs.gov/payments/direct-pay`).
- Exact user-facing messages (specs match them):
  - "This is an estimate. Verify with your accountant."
  - "Enter last year's total tax and AGI to use the safe harbor."
  - "Taxable income is above the QBI threshold (%{threshold}); the simplified QBI deduction may be too high."
  - "%{person}'s %{plan} contribution (%{amount}) is over the estimated limit (%{limit})."
  - "%{business}'s home office (%{amount}) is more than its profit; %{carryover} carries over."
  - "Federal tax figures for %{year} are incomplete."
  - "must be money paid out" (payment debit with a positive amount)
  - "is already recorded as a payment" (debit uniqueness)
  - "must start at $0 and rise" (brackets)
  - "is not a percentage like %{example}"
- Test output must stay clean: a passing `bundle exec rspec` prints only the reporter.
- TDD: each task writes its failing spec first and runs it to see it fail.
- Formatting: single spaces in literals, no column alignment. `bin/rubocop` must pass after every task.
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- **Parallel branch:** Goals (sub-project 8) may be built at the same time from `main`. It is expected to touch `db/schema.rb`, `lib/demo_seeder.rb`, the dashboard view and controller, `app/helpers/navigation_helper.rb`, `config/routes.rb`, and `docs/roadmap.md`. Keep edits to those files small and additive. Whichever merges second rebases; for `db/schema.rb`, re-run `bin/rails db:migrate` after the rebase rather than hand-merging.
- Kaneo: the controlling session (not task implementers) comments progress on GB-6 after each task and moves it to In Review when the PR opens.

## Review Focus

1. **Years at the edges**: `/taxes/2027` viewed in 2026 (no data yet), `/taxes/2025` (every period ended), `/taxes/1999`, `/taxes/abc`, `/taxes/010` → the first two render (no division by zero), the rest 404. (Pinned in Tasks 7 and 9.)
2. **A year with no `TaxParameters` row, or a mileage-only row**: the taxes page shows "Federal tax figures for 2025 are incomplete." with the payment log, never a 500; the dashboard card is hidden. (Pinned in Tasks 9 and 13.)
3. **Linking the wrong debit**: a positive transaction, a debit already linked, or a debit in a book the user can't access → a form error ("must be money paid out", "is already recorded as a payment") or 404, and nothing saved. (Pinned in Task 10.)
4. **Bracket row edits**: blank rows dropped, `37%` and `37` both accepted, rows out of order or not starting at $0 → "must start at $0 and rise", and `abc` → an error with nothing saved. Editing a mileage-only year's mileage rate still saves with the federal fields blank. (Pinned in Tasks 1 and 2.)
5. **A business with a loss plus a home office**: home office used is $0 and all of it carries over, SE tax never goes negative, and the loss offsets the same person's other business. (Pinned in Task 4.)

## File Map

```
app/models/concerns/percent_attribute.rb, sales_tax_profile.rb (refactor)            (Task 1)
db/migrate/20261012000001_add_federal_fields_to_tax_parameters.rb                    (Task 1)
app/models/tax_parameters.rb, tax_parameters/published.rb, db/seeds.rb,
  spec/factories/tax_parameters.rb                                                   (Task 1)
app/controllers/tax_parameters_controller.rb, views/tax_parameters/*                 (Task 2)
app/models/tax/due_dates.rb, tax/brackets.rb, tax/home_office_deduction.rb           pure (Task 3)
app/models/tax/params.rb, tax/inputs.rb (structs), tax/period_worksheet.rb,
  tax/period_calculator.rb, spec/support/tax_helpers.rb                              pure (Task 4)
app/models/tax/estimator.rb, tax/estimate.rb                                         pure (Task 5)
db/migrate/20261012000002_create_tax_records.rb, models household, tax_year,
  estimated_payment, home_office, person_adjustment, person, business, transaction    (Task 6)
app/models/tax.rb, tax/inputs.rb (load), reports/schedule_c_summary.rb               (Task 7)
app/controllers/households_controller.rb, views/households/edit, navigation_helper   (Task 8)
app/controllers/concerns/tax_year_param.rb, tax_years_controller.rb,
  views/tax_years/*, helpers/tax_years_helper.rb, routes, sidebar                    (Task 9)
app/models/tax/payment_candidates.rb, estimated_payments_controller.rb,
  views/estimated_payments/*                                                         (Task 10)
app/controllers/home_offices_controller.rb, views/home_offices/edit,
  schedule_cs controller/view                                                        (Task 11)
app/controllers/person_adjustments_controller.rb, views/person_adjustments/edit,
  views/people/index                                                                 (Task 12)
dashboards controller/view                                                           (Task 13)
lib/demo_seeder.rb                                                                   (Task 14)
spec/system/tax_engine_spec.rb, README.md, docs/roadmap.md                           (Task 15)
```

## Worked-example parameters

Every engine spec uses the 2026 figures (Task 1's `TaxParameters::Published`): standard deduction $32,200; brackets 10% from $0, 12% from $24,800, 22% from $100,800, 24% from $211,400, 32% from $403,550, 35% from $512,450, 37% from $768,700; wage base $184,500; SE earnings 92.35%; SS 12.4%; Medicare 2.9%; Additional Medicare 0.9% over $250,000; QBI 20%, threshold $403,500; home office $5/sq ft up to 300 sq ft; high-AGI threshold $150,000; annual additions $72,000; elective deferral $24,500. The expected numbers below were computed by hand with exact fractions and half-up rounding per line, and cross-checked with an independent script.

---

### Task 1: Percent attribute, federal tax parameters, 2026 values

**Files:**
- Create: `app/models/concerns/percent_attribute.rb`, `app/models/tax_parameters/published.rb`, `db/migrate/20261012000001_add_federal_fields_to_tax_parameters.rb`, `spec/models/concerns/percent_attribute_spec.rb`, `spec/models/tax_parameters_spec.rb`
- Modify: `app/models/sales_tax_profile.rb`, `app/models/tax_parameters.rb`, `db/seeds.rb`, `spec/factories/tax_parameters.rb`, `spec/db/seeds_spec.rb`

**Interfaces:**
- Produces: `PercentAttribute` (`percent_attribute(name, bps:, example:, allow_blank: false)`, `PercentAttribute.parse_bps(text) → Integer` raising `PercentAttribute::ParseError`, `PercentAttribute.format_bps(bps) → String`); `TaxParameters::FEDERAL_COLUMNS`; `TaxParameters#estimate_ready?`; `TaxParameters#bracket_rows` / `#bracket_rows=`; `TaxParameters::Published.fetch(year) → Hash` of column → value; factory trait `:federal_2026`. `TaxParameters#to_tax_params` arrives in Task 4.

- [ ] **Step 1: Write the failing specs**

`spec/models/concerns/percent_attribute_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PercentAttribute do
  it "parses percentages to basis points" do
    expect(described_class.parse_bps("9.25")).to eq(925)
    expect(described_class.parse_bps("9.25%")).to eq(925)
    expect(described_class.parse_bps(" 92.35 % ")).to eq(9235)
    expect(described_class.parse_bps("100")).to eq(10_000)
    expect(described_class.parse_bps("0")).to eq(0)
  end

  it "rejects anything else" do
    [ "", "abc", "9.255", "-1", "1000", "9,25" ].each do |input|
      expect { described_class.parse_bps(input) }.to raise_error(PercentAttribute::ParseError)
    end
  end

  it "formats basis points without trailing zeros" do
    expect(described_class.format_bps(925)).to eq("9.25")
    expect(described_class.format_bps(700)).to eq("7")
    expect(described_class.format_bps(1240)).to eq("12.4")
    expect(described_class.format_bps(9235)).to eq("92.35")
  end
end
```

`spec/models/tax_parameters_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe TaxParameters do
  it "is estimate-ready with the 2026 published figures" do
    expect(build(:tax_parameters, :federal_2026)).to be_estimate_ready
  end

  it "is not estimate-ready with only a mileage rate" do
    expect(build(:tax_parameters)).not_to be_estimate_ready
  end

  it "saves a mileage-only year with every federal field blank" do
    params = build(:tax_parameters, year: 2025, se_earnings_percent: "", standard_deduction_mfj: "", bracket_rows: [ { "floor" => "", "rate" => "" } ])
    expect(params).to be_valid
  end

  it "takes percentages and money as text" do
    params = build(:tax_parameters, se_earnings_percent: "92.35%", standard_deduction_mfj: "32,200")
    expect(params.se_earnings_bps).to eq(9235)
    expect(params.standard_deduction_mfj_cents).to eq(3_220_000)
  end

  it "reports a bad percentage" do
    params = build(:tax_parameters, ss_rate_percent: "abc")
    expect(params).not_to be_valid
    expect(params.errors[:ss_rate_percent]).to eq([ "is not a percentage like 12.4" ])
  end

  describe "bracket rows" do
    it "drops blank rows and accepts 37 or 37%" do
      params = build(:tax_parameters, bracket_rows: [
        { "floor" => "0", "rate" => "10" }, { "floor" => "24,800", "rate" => "12%" }, { "floor" => "", "rate" => "" }
      ])
      expect(params).to be_valid
      expect(params.brackets_mfj).to eq([ { "floor_cents" => 0, "rate_bps" => 1000 }, { "floor_cents" => 2_480_000, "rate_bps" => 1200 } ])
    end

    it "rejects rows that don't start at $0 or don't rise" do
      [ [ { "floor" => "100", "rate" => "10" } ],
        [ { "floor" => "0", "rate" => "10" }, { "floor" => "0", "rate" => "12" } ] ].each do |rows|
        params = build(:tax_parameters, bracket_rows: rows)
        expect(params).not_to be_valid
        expect(params.errors[:bracket_rows]).to eq([ "must start at $0 and rise" ])
      end
    end

    it "rejects a row that isn't a number" do
      params = build(:tax_parameters, bracket_rows: [ { "floor" => "0", "rate" => "abc" } ])
      expect(params).not_to be_valid
      expect(params.errors[:bracket_rows]).to eq([ "have an amount or rate that isn't a number" ])
    end

    it "shows saved brackets as text rows" do
      params = build(:tax_parameters, :federal_2026)
      expect(params.bracket_rows.first(2)).to eq([ { "floor" => "0.00", "rate" => "10" }, { "floor" => "24800.00", "rate" => "12" } ])
    end
  end
end
```

Replace `spec/db/seeds_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "db/seeds.rb" do
  it "creates reference data idempotently" do
    2.times { load Rails.root.join("db/seeds.rb") }
    params = TaxParameters.for_year(2026)
    expect(params.standard_mileage_rate_tenth_cents).to eq(725)
    expect(params).to be_estimate_ready
    expect(TaxParameters.count).to eq(1)
  end

  it "fills blank federal fields on an existing row without overwriting edits" do
    TaxParameters.create!(year: 2026, standard_mileage_rate_tenth_cents: 700, ss_wage_base_cents: 1)
    load Rails.root.join("db/seeds.rb")
    params = TaxParameters.for_year(2026)
    expect(params.standard_mileage_rate_tenth_cents).to eq(700)
    expect(params.ss_wage_base_cents).to eq(1)
    expect(params.standard_deduction_mfj_cents).to eq(3_220_000)
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/concerns/percent_attribute_spec.rb spec/models/tax_parameters_spec.rb spec/db/seeds_spec.rb`
Expected: FAIL (`uninitialized constant PercentAttribute`, unknown attributes).

- [ ] **Step 3: Migration**

`db/migrate/20261012000001_add_federal_fields_to_tax_parameters.rb`:

```ruby
class AddFederalFieldsToTaxParameters < ActiveRecord::Migration[8.1]
  def change
    change_table :tax_parameters, bulk: true do |t|
      t.integer :standard_deduction_mfj_cents
      t.json :brackets_mfj
      t.integer :ss_wage_base_cents
      t.integer :se_earnings_bps
      t.integer :ss_rate_bps
      t.integer :medicare_rate_bps
      t.integer :additional_medicare_bps
      t.integer :additional_medicare_threshold_mfj_cents
      t.integer :qbi_bps
      t.integer :qbi_threshold_mfj_cents
      t.integer :home_office_simplified_rate_cents
      t.integer :home_office_simplified_max_sqft
      t.integer :safe_harbor_high_agi_threshold_cents
      t.integer :annual_additions_limit_cents
      t.integer :elective_deferral_limit_cents
    end
  end
end
```

Run: `bin/rails db:migrate` (updates `db/schema.rb`).

- [ ] **Step 4: `PercentAttribute`**

`app/models/concerns/percent_attribute.rb`:

```ruby
# Exposes an integer basis-point column as percentage text: "9.25", "9.25%" ↔ 925.
module PercentAttribute
  extend ActiveSupport::Concern

  class ParseError < ArgumentError; end

  FORMAT = /\A\d{1,3}(\.\d{1,2})?\z/

  def self.parse_bps(input)
    text = input.to_s.strip.delete_suffix("%").strip
    raise ParseError, "is not a percentage" unless text.match?(FORMAT)

    (Rational(text) * 100).to_i
  end

  def self.format_bps(bps)
    value = Rational(bps, 100)
    value.denominator == 1 ? value.to_i.to_s : format("%.2f", value).sub(/0\z/, "")
  end

  class_methods do
    def percent_attribute(name, bps:, example:, allow_blank: false)
      input_ivar = "@#{name}_input"
      invalid_ivar = "@#{name}_invalid"

      define_method(name) do
        if instance_variable_defined?(input_ivar)
          instance_variable_get(input_ivar)
        elsif self[bps]
          PercentAttribute.format_bps(self[bps])
        end
      end

      define_method("#{name}=") do |input|
        instance_variable_set(input_ivar, input)
        instance_variable_set(invalid_ivar, false)
        self[bps] = allow_blank && input.to_s.strip.empty? ? nil : PercentAttribute.parse_bps(input)
      rescue ParseError
        self[bps] = nil
        instance_variable_set(invalid_ivar, true)
      end

      validate do
        errors.add(name, "is not a percentage like #{example}") if instance_variable_get(invalid_ivar)
      end
    end
  end
end
```

- [ ] **Step 5: Move `SalesTaxProfile` onto it**

In `app/models/sales_tax_profile.rb`: add `include PercentAttribute` at the top of the class and `percent_attribute :default_rate_percent, bps: :default_rate_bps, example: "9.25"` under the validations. Delete the hand-written `default_rate_percent`, `default_rate_percent=`, `validate :default_rate_percent_parses`, and `default_rate_percent_parses`. The `default_rate_bps` numericality validation (`1..2_000`) stays and still enforces the 20% cap.

Run: `bundle exec rspec spec/models/sales_tax_profile_spec.rb spec/requests/sales_tax_profiles_spec.rb` → PASS, unchanged.

- [ ] **Step 6: Published 2026 values**

`app/models/tax_parameters/published.rb`:

```ruby
# Federal figures as published, keyed by tax year. Seeds and the demo copy them; the household owner can edit the stored row.
class TaxParameters
  module Published
    YEARS = {
      2026 => {
        standard_mileage_rate_tenth_cents: 725, # IRS Notice 2026 standard mileage rates: 72.5¢/mile
        standard_deduction_mfj_cents: 3_220_000, # Rev. Proc. 2025-32: $32,200 MFJ
        brackets_mfj: [ # Rev. Proc. 2025-32, MFJ
          { "floor_cents" => 0, "rate_bps" => 1000 },
          { "floor_cents" => 2_480_000, "rate_bps" => 1200 },
          { "floor_cents" => 10_080_000, "rate_bps" => 2200 },
          { "floor_cents" => 21_140_000, "rate_bps" => 2400 },
          { "floor_cents" => 40_355_000, "rate_bps" => 3200 },
          { "floor_cents" => 51_245_000, "rate_bps" => 3500 },
          { "floor_cents" => 76_870_000, "rate_bps" => 3700 }
        ],
        ss_wage_base_cents: 18_450_000, # SSA 2026 COLA fact sheet: $184,500
        se_earnings_bps: 9235, # IRC §1402(a)(12)
        ss_rate_bps: 1240, # IRC §1401(a)
        medicare_rate_bps: 290, # IRC §1401(b)(1)
        additional_medicare_bps: 90, # IRC §1401(b)(2)
        additional_medicare_threshold_mfj_cents: 25_000_000, # IRC §1401(b)(2)(A), not indexed
        qbi_bps: 2000, # IRC §199A(a)
        qbi_threshold_mfj_cents: 40_350_000, # Rev. Proc. 2025-32: $403,500 MFJ
        home_office_simplified_rate_cents: 500, # Rev. Proc. 2013-13
        home_office_simplified_max_sqft: 300, # Rev. Proc. 2013-13
        safe_harbor_high_agi_threshold_cents: 15_000_000, # IRC §6654(d)(1)(C)
        annual_additions_limit_cents: 7_200_000, # IRS 2026 retirement plan COLA notice, §415(c)
        elective_deferral_limit_cents: 2_450_000 # IRS 2026 retirement plan COLA notice, §402(g)
      }
    }.freeze

    def self.fetch(year) = YEARS.fetch(year)
  end
end
```

Before committing, check every value against its source (the IRS 2026 inflation-adjustment news release / Rev. Proc. 2025-32, the SSA 2026 fact sheet, the IRS 2026 retirement-plan limits release, the IRS 2026 mileage notice). If a source disagrees, use the source's value and update the "Worked-example parameters" section of this plan and the spec's §7 table; the expected numbers in Tasks 4–5 then need recomputing.

- [ ] **Step 7: `TaxParameters`**

Replace `app/models/tax_parameters.rb`:

```ruby
class TaxParameters < ApplicationRecord
  include MoneyAttribute
  include PercentAttribute

  self.table_name = "tax_parameters"

  FEDERAL_COLUMNS = %i[
    standard_deduction_mfj_cents ss_wage_base_cents se_earnings_bps ss_rate_bps medicare_rate_bps additional_medicare_bps
    additional_medicare_threshold_mfj_cents qbi_bps qbi_threshold_mfj_cents home_office_simplified_rate_cents
    home_office_simplified_max_sqft safe_harbor_high_agi_threshold_cents annual_additions_limit_cents elective_deferral_limit_cents
  ].freeze

  money_attribute :standard_deduction_mfj, allow_blank: true
  money_attribute :ss_wage_base, allow_blank: true
  money_attribute :additional_medicare_threshold_mfj, allow_blank: true
  money_attribute :qbi_threshold_mfj, allow_blank: true
  money_attribute :home_office_simplified_rate, allow_blank: true
  money_attribute :safe_harbor_high_agi_threshold, allow_blank: true
  money_attribute :annual_additions_limit, allow_blank: true
  money_attribute :elective_deferral_limit, allow_blank: true
  percent_attribute :se_earnings_percent, bps: :se_earnings_bps, example: "92.35", allow_blank: true
  percent_attribute :ss_rate_percent, bps: :ss_rate_bps, example: "12.4", allow_blank: true
  percent_attribute :medicare_rate_percent, bps: :medicare_rate_bps, example: "2.9", allow_blank: true
  percent_attribute :additional_medicare_percent, bps: :additional_medicare_bps, example: "0.9", allow_blank: true
  percent_attribute :qbi_percent, bps: :qbi_bps, example: "20", allow_blank: true

  validates :year, presence: true, uniqueness: true, numericality: { only_integer: true, in: 2000..2100 }
  validates :standard_mileage_rate_tenth_cents, numericality: { only_integer: true, greater_than: 0, less_than: 2_147_483_647 }, unless: -> { @mileage_rate_error }
  validates :home_office_simplified_max_sqft, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate { errors.add(:mileage_rate_cents, @mileage_rate_error) if @mileage_rate_error }
  validate :brackets_valid

  def self.for_year(year) = find_by(year: year)

  def self.model_name = ActiveModel::Name.new(self, nil, "TaxParameter")

  def estimate_ready?
    FEDERAL_COLUMNS.all? { self[_1].present? } && brackets_mfj.present? && brackets_rise?(brackets_mfj)
  end

  def mileage_rate_cents
    @mileage_rate_input || (standard_mileage_rate_tenth_cents && Tenths.format(standard_mileage_rate_tenth_cents))
  end

  def mileage_rate_cents=(input)
    @mileage_rate_input = input
    @mileage_rate_error = nil
    self.standard_mileage_rate_tenth_cents = Tenths.parse(input)
  rescue Tenths::ParseError => e
    self.standard_mileage_rate_tenth_cents = nil
    @mileage_rate_error = e.message
  end

  def bracket_rows
    @bracket_rows_input || Array(brackets_mfj).map do |bracket|
      { "floor" => Money.new(bracket.fetch("floor_cents")).to_input, "rate" => PercentAttribute.format_bps(bracket.fetch("rate_bps")) }
    end
  end

  def bracket_rows=(rows)
    @bracket_rows_input = Array(rows).map { _1.to_h.stringify_keys.slice("floor", "rate") }
    @bracket_rows_error = nil
    filled = @bracket_rows_input.reject { |row| row.values.all?(&:blank?) }
    self.brackets_mfj = filled.empty? ? nil : filled.map { { "floor_cents" => Money.parse(_1["floor"]).cents, "rate_bps" => PercentAttribute.parse_bps(_1["rate"]) } }
  rescue Money::ParseError, PercentAttribute::ParseError
    @bracket_rows_error = "have an amount or rate that isn't a number"
  end

  private

  def brackets_valid
    return errors.add(:bracket_rows, @bracket_rows_error) if @bracket_rows_error
    return if brackets_mfj.blank?

    errors.add(:bracket_rows, "must start at $0 and rise") unless brackets_rise?(brackets_mfj)
  end

  def brackets_rise?(brackets)
    floors = brackets.map { _1["floor_cents"] }
    rates = brackets.map { _1["rate_bps"] }
    floors.first == 0 && floors.each_cons(2).all? { _1 < _2 } && rates.all? { (0..10_000).cover?(_1) }
  end
end
```

Check `Money#to_input` for `0` returns `"0.00"` and for 2_480_000 returns `"24800.00"`; if its format differs, update the `"shows saved brackets as text rows"` expectation to match `to_input`, not the other way round.

- [ ] **Step 8: Factory trait and seeds**

`spec/factories/tax_parameters.rb`:

```ruby
FactoryBot.define do
  factory :tax_parameters do
    year { 2026 }
    standard_mileage_rate_tenth_cents { 725 }

    trait :federal_2026 do
      after(:build) { |params| params.assign_attributes(TaxParameters::Published.fetch(2026).except(:standard_mileage_rate_tenth_cents)) }
    end
  end
end
```

Replace the `TaxParameters` block in `db/seeds.rb`:

```ruby
TaxParameters::Published::YEARS.each do |year, values|
  params = TaxParameters.find_or_create_by!(year: year) do |row|
    row.standard_mileage_rate_tenth_cents = values.fetch(:standard_mileage_rate_tenth_cents)
  end
  blanks = values.select { |column, _| params[column].nil? }
  params.update!(blanks) if blanks.any?
end
```

- [ ] **Step 9: Run the specs**

Run: `bundle exec rspec spec/models/concerns/percent_attribute_spec.rb spec/models/tax_parameters_spec.rb spec/db/seeds_spec.rb spec/requests/tax_parameters_spec.rb spec/models/sales_tax_profile_spec.rb` → PASS. Then `bundle exec rspec` and `bin/rubocop` → clean.

- [ ] **Step 10: Commit**

```bash
git add app/models db spec
git commit -m "Tax engine: percent attribute, federal tax parameters, 2026 figures

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Tax parameters form

**Files:**
- Modify: `app/controllers/tax_parameters_controller.rb`, `app/views/tax_parameters/_form.html.erb`, `app/views/tax_parameters/index.html.erb`, `spec/requests/tax_parameters_spec.rb`

**Interfaces:**
- Consumes: Task 1's `TaxParameters` attributes (`*_percent`, money names without `_cents`, `bracket_rows`, `estimate_ready?`).

- [ ] **Step 1: Write the failing request specs**

Append inside the `RSpec.describe` block of `spec/requests/tax_parameters_spec.rb`:

```ruby
  describe "federal figures" do
    let(:federal) do
      { mileage_rate_cents: "72.5", standard_deduction_mfj: "32,200", ss_wage_base: "184,500", se_earnings_percent: "92.35",
        ss_rate_percent: "12.4", medicare_rate_percent: "2.9", additional_medicare_percent: "0.9", additional_medicare_threshold_mfj: "250,000",
        qbi_percent: "20", qbi_threshold_mfj: "403,500", home_office_simplified_rate: "5", home_office_simplified_max_sqft: "300",
        safe_harbor_high_agi_threshold: "150,000", annual_additions_limit: "72,000", elective_deferral_limit: "24,500",
        bracket_rows: [ { floor: "0", rate: "10" }, { floor: "24,800", rate: "12%" }, { floor: "", rate: "" } ] }
    end

    it "saves every federal field and drops blank bracket rows" do
      tp = create(:tax_parameters)
      sign_in_as create(:user, :household_owner)
      patch tax_parameter_path(tp), params: { tax_parameter: federal }
      expect(response).to redirect_to(tax_parameters_path)
      tp.reload
      expect(tp.se_earnings_bps).to eq(9235)
      expect(tp.home_office_simplified_max_sqft).to eq(300)
      expect(tp.brackets_mfj.size).to eq(2)
      expect(tp).to be_estimate_ready
    end

    it "still saves a mileage-only edit with the federal fields blank" do
      tp = create(:tax_parameters, year: 2025)
      sign_in_as create(:user, :household_owner)
      patch tax_parameter_path(tp), params: { tax_parameter: { mileage_rate_cents: "70", standard_deduction_mfj: "", se_earnings_percent: "",
                                                               bracket_rows: [ { floor: "", rate: "" } ] } }
      expect(response).to redirect_to(tax_parameters_path)
      expect(tp.reload.standard_mileage_rate_tenth_cents).to eq(700)
    end

    it "re-renders brackets that don't rise, keeping the rows typed" do
      tp = create(:tax_parameters, :federal_2026)
      sign_in_as create(:user, :household_owner)
      patch tax_parameter_path(tp), params: { tax_parameter: { bracket_rows: [ { floor: "100", rate: "10" } ] } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must start at $0 and rise")
      expect(response.body).to include('value="100"')
      expect(tp.reload.brackets_mfj.size).to eq(7)
    end

    it "shows two blank bracket rows after the saved ones" do
      tp = create(:tax_parameters, :federal_2026)
      sign_in_as create(:user, :household_owner)
      get edit_tax_parameter_path(tp)
      expect(response.body.scan('name="tax_parameter[bracket_rows][][floor]"').size).to eq(9)
    end

    it "marks each year complete or incomplete on the list" do
      create(:tax_parameters, :federal_2026)
      create(:tax_parameters, year: 2025)
      sign_in_as create(:user, :household_owner)
      get tax_parameters_path
      expect(response.body).to include("Complete").and include("Mileage only")
    end
  end
```

- [ ] **Step 2: Run to see them fail**

Run: `bundle exec rspec spec/requests/tax_parameters_spec.rb`
Expected: FAIL (unpermitted params are dropped, so nothing saves; no "Complete").

- [ ] **Step 3: Controller params**

In `app/controllers/tax_parameters_controller.rb`, add:

```ruby
  FEDERAL_FIELDS = %i[
    standard_deduction_mfj ss_wage_base additional_medicare_threshold_mfj qbi_threshold_mfj home_office_simplified_rate
    safe_harbor_high_agi_threshold annual_additions_limit elective_deferral_limit se_earnings_percent ss_rate_percent
    medicare_rate_percent additional_medicare_percent qbi_percent home_office_simplified_max_sqft
  ].freeze
```

and change the two `params.expect` calls to private helpers:

```ruby
  def create_params = params.expect(tax_parameter: [ :year, :mileage_rate_cents, *FEDERAL_FIELDS, bracket_rows: [ [ :floor, :rate ] ] ])
  def update_params = params.expect(tax_parameter: [ :mileage_rate_cents, *FEDERAL_FIELDS, bracket_rows: [ [ :floor, :rate ] ] ])
```

`create` uses `TaxParameters.new(create_params)`; `update` uses `@tax_parameters.update(update_params)`. In `new`, prefill a year that has published values: `@tax_parameters = TaxParameters.new(year: year_param); @tax_parameters.assign_attributes(TaxParameters::Published::YEARS.fetch(year_param, {}))`.

- [ ] **Step 4: Form**

Replace `app/views/tax_parameters/_form.html.erb`:

```erb
<%= form_with model: tax_parameters do |f| %>
  <%= render "shared/errors", record: tax_parameters %>
  <p><%= f.label :year %> <%= f.number_field :year, disabled: tax_parameters.persisted? %></p>
  <p><%= f.label :mileage_rate_cents, "IRS standard mileage rate (cents per mile)" %> <%= f.text_field :mileage_rate_cents, size: 6 %></p>

  <h2>Federal estimated tax</h2>
  <p class="muted">From the IRS's annual inflation adjustments. Leave blank for a year you only track mileage in.</p>
  <p><%= f.label :standard_deduction_mfj, "Standard deduction, married filing jointly ($)" %> <%= f.text_field :standard_deduction_mfj, size: 12 %></p>

  <fieldset>
    <legend>Tax brackets, married filing jointly</legend>
    <table>
      <thead><tr><th>Taxable income from ($)</th><th>Rate (%)</th></tr></thead>
      <tbody>
        <% (tax_parameters.bracket_rows + [ {}, {} ]).each do |row| %>
          <tr>
            <td><%= text_field_tag "tax_parameter[bracket_rows][][floor]", row["floor"], size: 12, "aria-label": "Bracket floor" %></td>
            <td><%= text_field_tag "tax_parameter[bracket_rows][][rate]", row["rate"], size: 6, "aria-label": "Bracket rate" %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </fieldset>

  <fieldset>
    <legend>Self-employment tax</legend>
    <p><%= f.label :se_earnings_percent, "Share of profit subject to SE tax (%)" %> <%= f.text_field :se_earnings_percent, size: 6 %></p>
    <p><%= f.label :ss_rate_percent, "Social Security rate (%)" %> <%= f.text_field :ss_rate_percent, size: 6 %></p>
    <p><%= f.label :ss_wage_base, "Social Security wage base ($)" %> <%= f.text_field :ss_wage_base, size: 12 %></p>
    <p><%= f.label :medicare_rate_percent, "Medicare rate (%)" %> <%= f.text_field :medicare_rate_percent, size: 6 %></p>
    <p><%= f.label :additional_medicare_percent, "Additional Medicare rate (%)" %> <%= f.text_field :additional_medicare_percent, size: 6 %></p>
    <p><%= f.label :additional_medicare_threshold_mfj, "Additional Medicare threshold, MFJ ($)" %> <%= f.text_field :additional_medicare_threshold_mfj, size: 12 %></p>
  </fieldset>

  <fieldset>
    <legend>Deductions and limits</legend>
    <p><%= f.label :qbi_percent, "QBI deduction (%)" %> <%= f.text_field :qbi_percent, size: 6 %></p>
    <p><%= f.label :qbi_threshold_mfj, "QBI threshold, MFJ ($)" %> <%= f.text_field :qbi_threshold_mfj, size: 12 %></p>
    <p><%= f.label :home_office_simplified_rate, "Simplified home office rate ($ per sq ft)" %> <%= f.text_field :home_office_simplified_rate, size: 6 %></p>
    <p><%= f.label :home_office_simplified_max_sqft, "Simplified home office maximum (sq ft)" %> <%= f.number_field :home_office_simplified_max_sqft, min: 1 %></p>
    <p><%= f.label :safe_harbor_high_agi_threshold, "Safe harbor 110% applies above prior-year AGI of ($)" %> <%= f.text_field :safe_harbor_high_agi_threshold, size: 12 %></p>
    <p><%= f.label :annual_additions_limit, "Retirement annual additions limit ($)" %> <%= f.text_field :annual_additions_limit, size: 12 %></p>
    <p><%= f.label :elective_deferral_limit, "401(k) elective deferral limit ($)" %> <%= f.text_field :elective_deferral_limit, size: 12 %></p>
  </fieldset>
  <%= f.submit %>
<% end %>
```

The bracket error is on `:bracket_rows`; `shared/_errors` lists full messages, so it reads "Bracket rows must start at $0 and rise".

- [ ] **Step 5: Index status column**

In `app/views/tax_parameters/index.html.erb`, add a "Federal figures" column whose cell is `params.estimate_ready? ? "Complete" : "Mileage only"` (use the loop variable the view already has).

- [ ] **Step 6: Run the specs, rubocop, commit**

Run: `bundle exec rspec spec/requests/tax_parameters_spec.rb` → PASS; `bin/rubocop` clean.

```bash
git add app spec
git commit -m "Tax engine: federal fields and bracket rows on the tax parameters form

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Pure due dates, brackets, home office deduction

**Files:**
- Create: `app/models/tax/due_dates.rb`, `app/models/tax/brackets.rb`, `app/models/tax/home_office_deduction.rb`, `app/models/tax/bracket.rb`, `app/models/tax/params.rb`
- Test: `spec/models/tax/due_dates_spec.rb`, `spec/models/tax/brackets_spec.rb`, `spec/models/tax/home_office_deduction_spec.rb`

**Interfaces:**
- Produces:
  - `Tax::DueDates.for(year) → [Date, Date, Date, Date]`, `Tax::DueDates.roll(date) → Date`, `Tax::DueDates.quarter_on(year, date) → 1..4` (the first installment due on or after `date`, else 4).
  - `Tax::Bracket = Data.define(:floor_cents, :rate_bps)`.
  - `Tax::Brackets.slices(taxable_cents, brackets) → [Tax::Brackets::Slice]` with `Slice = Data.define(:rate_bps, :from_cents, :to_cents, :taxed_cents, :tax_cents)`; `Tax::Brackets.tax_cents(taxable_cents, brackets) → Integer`.
  - `Tax::HomeOfficeDeduction.cents(home_office, rate_cents:, max_sqft:) → Integer`. `home_office` responds to `calculation`, `office_sqft`, `home_sqft`, `rent_cents`, `mortgage_interest_cents`, `utilities_cents`, `insurance_cents`, `repairs_cents`, `other_cents`, `depreciation_cents`. Uncapped (capping happens in the calculator and Schedule C).

- [ ] **Step 1: Write the failing specs**

`spec/models/tax/due_dates_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tax::DueDates do
  it "uses the plain dates when they're business days (2026)" do
    expect(described_class.for(2026)).to eq([ Date.new(2026, 4, 15), Date.new(2026, 6, 15), Date.new(2026, 9, 15), Date.new(2027, 1, 15) ])
  end

  it "rolls past a weekend and Emancipation Day observed" do
    expect(described_class.for(2017).first).to eq(Date.new(2017, 4, 18)) # Sat 15 → Sun → Mon 17 observed (16th a Sunday) → Tue 18
    expect(described_class.for(2022).first).to eq(Date.new(2022, 4, 18)) # Fri 15 observed (16th a Saturday) → Sat → Sun → Mon 18
    expect(described_class.for(2023).first).to eq(Date.new(2023, 4, 18)) # Sat 15 → Sun → Mon 17 observed → Tue 18
  end

  it "rolls past MLK Day" do
    expect(described_class.for(2023).last).to eq(Date.new(2024, 1, 16)) # Mon Jan 15, 2024 is MLK Day
    expect(described_class.for(2027).last).to eq(Date.new(2028, 1, 18)) # Sat 15 → Sun → Mon 17 MLK → Tue 18
  end

  it "rolls a Sunday June 15 to Monday" do
    expect(described_class.for(2025)[1]).to eq(Date.new(2025, 6, 16))
  end

  describe ".quarter_on" do
    it "picks the first installment due on or after the date" do
      expect(described_class.quarter_on(2026, Date.new(2026, 1, 2))).to eq(1)
      expect(described_class.quarter_on(2026, Date.new(2026, 4, 15))).to eq(1)
      expect(described_class.quarter_on(2026, Date.new(2026, 4, 16))).to eq(2)
      expect(described_class.quarter_on(2026, Date.new(2026, 9, 16))).to eq(4)
      expect(described_class.quarter_on(2026, Date.new(2027, 1, 10))).to eq(4)
    end

    it "falls back to 4 after the last due date" do
      expect(described_class.quarter_on(2026, Date.new(2027, 3, 1))).to eq(4)
    end
  end
end
```

`spec/models/tax/brackets_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tax::Brackets do
  let(:brackets) { [ Tax::Bracket.new(floor_cents: 0, rate_bps: 1000), Tax::Bracket.new(floor_cents: 2_480_000, rate_bps: 1200), Tax::Bracket.new(floor_cents: 10_080_000, rate_bps: 2200) ] }

  it "taxes nothing at zero" do
    expect(described_class.slices(0, brackets)).to eq([])
    expect(described_class.tax_cents(0, brackets)).to eq(0)
  end

  it "slices progressively and rounds each slice once" do
    # $48,588.18: 10% × 24,800.00 = 2,480.00; 12% × 23,788.18 = 2,854.5816 → 2,854.58
    slices = described_class.slices(4_858_818, brackets)
    expect(slices.map(&:tax_cents)).to eq([ 248_000, 285_458 ])
    expect(slices.last).to have_attributes(rate_bps: 1200, from_cents: 2_480_000, to_cents: 4_858_818, taxed_cents: 2_378_818)
    expect(described_class.tax_cents(4_858_818, brackets)).to eq(533_458)
  end

  it "uses the top bracket without an upper bound" do
    # $200,000: 2,480.00 + 12% × 76,000.00 = 9,120.00 + 22% × 99,200.00 = 21,824.00
    expect(described_class.tax_cents(20_000_000, brackets)).to eq(248_000 + 912_000 + 2_182_400)
  end

  it "stops exactly at a floor" do
    expect(described_class.slices(2_480_000, brackets).size).to eq(1)
  end
end
```

`spec/models/tax/home_office_deduction_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tax::HomeOfficeDeduction do
  Office = Struct.new(:calculation, :office_sqft, :home_sqft, :rent_cents, :mortgage_interest_cents, :utilities_cents,
                      :insurance_cents, :repairs_cents, :other_cents, :depreciation_cents, keyword_init: true)

  def office(**attrs)
    Office.new(calculation: "simplified", office_sqft: 200, home_sqft: nil, rent_cents: 0, mortgage_interest_cents: 0, utilities_cents: 0,
               insurance_cents: 0, repairs_cents: 0, other_cents: 0, depreciation_cents: 0, **attrs)
  end

  it "multiplies square feet by the rate for the simplified method" do
    expect(described_class.cents(office(office_sqft: 200), rate_cents: 500, max_sqft: 300)).to eq(100_000)
  end

  it "caps simplified square feet at the maximum" do
    expect(described_class.cents(office(office_sqft: 350), rate_cents: 500, max_sqft: 300)).to eq(150_000)
  end

  it "takes the office share of home costs plus depreciation for the regular method" do
    # 200 / 2,000 × (24,000 + 3,600 + 1,200) = 2,880.00, + 500.00 depreciation
    regular = office(calculation: "regular", office_sqft: 200, home_sqft: 2_000, rent_cents: 2_400_000, utilities_cents: 360_000,
                     insurance_cents: 120_000, depreciation_cents: 50_000)
    expect(described_class.cents(regular, rate_cents: 500, max_sqft: 300)).to eq(338_000)
  end

  it "rounds the regular share once" do
    # 1 / 3 × 100.00 = 33.333… → 33.33
    regular = office(calculation: "regular", office_sqft: 1, home_sqft: 3, other_cents: 10_000)
    expect(described_class.cents(regular, rate_cents: 500, max_sqft: 300)).to eq(3_333)
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/tax`
Expected: FAIL (`uninitialized constant Tax`).

- [ ] **Step 3: Implement**

One constant per file, so Zeitwerk can autoload each by name.

`app/models/tax/bracket.rb`:

```ruby
module Tax
  Bracket = Data.define(:floor_cents, :rate_bps)
end
```

`app/models/tax/params.rb`:

```ruby
module Tax
  # One year's federal figures as the engine reads them (built by TaxParameters#to_tax_params).
  Params = Data.define(
    :standard_deduction_cents, :brackets, :ss_wage_base_cents, :se_earnings_bps, :ss_rate_bps, :medicare_rate_bps,
    :additional_medicare_bps, :additional_medicare_threshold_cents, :qbi_bps, :qbi_threshold_cents,
    :home_office_rate_cents, :home_office_max_sqft, :safe_harbor_high_agi_threshold_cents,
    :annual_additions_limit_cents, :elective_deferral_limit_cents
  )
end
```

`app/models/tax/due_dates.rb`:

```ruby
module Tax
  # Estimated tax installments are due Apr 15, Jun 15, Sep 15, and Jan 15, rolled past weekends and holidays. Only two holidays
  # can land on a roll date: MLK Day (third Monday of January, Jan 15–21) and DC Emancipation Day observed (Apr 15–17).
  module DueDates
    module_function

    def for(year)
      [ Date.new(year, 4, 15), Date.new(year, 6, 15), Date.new(year, 9, 15), Date.new(year + 1, 1, 15) ].map { roll(_1) }
    end

    def roll(date)
      date += 1 while date.saturday? || date.sunday? || holiday?(date)
      date
    end

    def quarter_on(year, date)
      (self.for(year).index { date <= _1 } || 3) + 1
    end

    def holiday?(date) = mlk_day?(date) || emancipation_day_observed?(date)

    def mlk_day?(date) = date.month == 1 && date.monday? && (15..21).cover?(date.day)

    def emancipation_day_observed?(date)
      return false unless date.month == 4

      day = Date.new(date.year, 4, 16)
      day -= 1 if day.saturday?
      day += 1 if day.sunday?
      date == day
    end
  end
end
```

`app/models/tax/brackets.rb`:

```ruby
module Tax
  module Brackets
    Slice = Data.define(:rate_bps, :from_cents, :to_cents, :taxed_cents, :tax_cents)

    module_function

    def slices(taxable_cents, brackets)
      brackets.each_with_index.filter_map do |bracket, index|
        next if taxable_cents <= bracket.floor_cents

        ceiling = brackets[index + 1]&.floor_cents
        upper = ceiling ? [ taxable_cents, ceiling ].min : taxable_cents
        taxed = upper - bracket.floor_cents
        Slice.new(rate_bps: bracket.rate_bps, from_cents: bracket.floor_cents, to_cents: upper, taxed_cents: taxed,
                  tax_cents: Money.round_rational(Rational(taxed * bracket.rate_bps, 10_000)))
      end
    end

    def tax_cents(taxable_cents, brackets) = slices(taxable_cents, brackets).sum(&:tax_cents)
  end
end
```

`app/models/tax/home_office_deduction.rb`:

```ruby
module Tax
  module HomeOfficeDeduction
    COST_COLUMNS = %i[rent_cents mortgage_interest_cents utilities_cents insurance_cents repairs_cents other_cents].freeze

    module_function

    def cents(home_office, rate_cents:, max_sqft:)
      if home_office.calculation == "simplified"
        [ home_office.office_sqft, max_sqft ].min * rate_cents
      else
        costs = COST_COLUMNS.sum { home_office.public_send(_1) }
        Money.round_rational(Rational(home_office.office_sqft * costs, home_office.home_sqft)) + home_office.depreciation_cents
      end
    end
  end
end
```

- [ ] **Step 4: Run, rubocop, commit**

Run: `bundle exec rspec spec/models/tax` → PASS; `bin/rubocop` clean. (RuboCop may flag the `Office` constant inside the `describe` block via `Lint/ConstantDefinitionInBlock`; if so, use `let(:office_class) { Struct.new(...) }` instead.)

```bash
git add app/models/tax spec/models/tax
git commit -m "Tax engine: due dates, brackets, home office deduction (pure)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Period calculator

**Files:**
- Create: `app/models/tax/business_input.rb`, `app/models/tax/person_input.rb`, `app/models/tax/period_input.rb`, `app/models/tax/prior_year.rb`, `app/models/tax/payment.rb`, `app/models/tax/inputs.rb` (the struct; `load` arrives in Task 7), `app/models/tax/period_worksheet.rb`, `app/models/tax/period_calculator.rb`, `spec/support/tax_helpers.rb`
- Modify: `app/models/tax_parameters.rb` (`to_tax_params`)
- Test: `spec/models/tax/period_calculator_spec.rb`

**Interfaces:**
- Consumes: `Tax::Params`, `Tax::Bracket`, `Tax::Brackets` (Task 3).
- Produces:
  - `TaxParameters#to_tax_params → Tax::Params`.
  - `Tax::BusinessInput = Data.define(:id, :name, :person_id, :home_office_cents)`.
  - `Tax::PersonInput = Data.define(:id, :name, :se_health_insurance_cents, :retirement_contribution_cents, :retirement_plan)`.
  - `Tax::PeriodInput = Data.define(:quarter, :factor, :elapsed_days, :profit_cents_by_business)`. `elapsed_days` is nil when the period has ended; `profit_cents_by_business` maps business id → YTD profit before home office.
  - `Tax::PriorYear = Data.define(:total_tax_cents, :agi_cents)`, `Tax::Payment = Data.define(:quarter, :amount_cents)`.
  - `Tax::Inputs = Data.define(:year, :params, :businesses, :people, :periods, :prior_year, :payments, :today)`.
  - `Tax::PeriodCalculator.call(params:, businesses:, people:, period:) → Tax::PeriodWorksheet`.
  - `Tax::PeriodWorksheet` attributes: `quarter factor elapsed_days business_lines person_lines additional_medicare_cents total_net_profit_cents agi_cents standard_deduction_cents taxable_before_qbi_cents qbi_cents qbi_deduction_cents taxable_income_cents bracket_slices income_tax_cents`; methods `se_tax_cents`, `total_tax_cents`.
  - `Tax::PeriodWorksheet::BusinessLine` (`business ytd_cents annualized_cents home_office_cents home_office_used_cents carryover_cents net_profit_cents`) and `PersonLine` (`person net_profit_cents se_earnings_cents ss_cents medicare_cents half_se_cents retirement_cents health_insurance_cents`, method `se_tax_cents`).
  - Spec helpers `tax_params_2026`, `tax_business`, `tax_person`, `tax_period`, `tax_periods`, `tax_inputs`.

- [ ] **Step 1: Spec helpers**

`spec/support/tax_helpers.rb`:

```ruby
module TaxHelpers
  FACTORS = { 1 => 4, 2 => Rational(12, 5), 3 => Rational(3, 2), 4 => 1 }.freeze

  def tax_params_2026 = FactoryBot.build(:tax_parameters, :federal_2026).to_tax_params

  def tax_business(id, person_id: id, home_office_cents: 0) = Tax::BusinessInput.new(id:, name: "Business #{id}", person_id:, home_office_cents:)

  def tax_person(id, health: 0, retirement: 0, plan: nil)
    Tax::PersonInput.new(id:, name: "Person #{id}", se_health_insurance_cents: health, retirement_contribution_cents: retirement, retirement_plan: plan)
  end

  # profits: { business_id => YTD cents }
  def tax_period(quarter, profits, factor: FACTORS.fetch(quarter), elapsed_days: nil)
    Tax::PeriodInput.new(quarter:, factor:, elapsed_days:, profit_cents_by_business: profits)
  end

  # ytd: { quarter => { business_id => YTD cents } }
  def tax_periods(ytd) = ytd.map { |quarter, profits| tax_period(quarter, profits) }

  def tax_inputs(ytd:, businesses: [ tax_business(1) ], people: [ tax_person(1) ], prior_year: nil, payments: [], today: Date.new(2027, 2, 1))
    Tax::Inputs.new(year: 2026, params: tax_params_2026, businesses:, people:, periods: tax_periods(ytd), prior_year:, payments:, today:)
  end
end

RSpec.configure { |config| config.include TaxHelpers }
```

- [ ] **Step 2: Write the failing spec**

`spec/models/tax/period_calculator_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tax::PeriodCalculator do
  def worksheet(profits, businesses: profits.keys.map { tax_business(_1) }, people: businesses.map(&:person_id).uniq.map { tax_person(_1) }, **period)
    described_class.call(params: tax_params_2026, businesses:, people:, period: tax_period(period.delete(:quarter) || 4, profits, **period))
  end

  it "owes nothing on zero profit" do
    result = worksheet({ 1 => 0 })
    expect(result.total_tax_cents).to eq(0)
    expect(result.person_lines.first.se_earnings_cents).to eq(0)
  end

  it "skips SE tax when SE earnings are under $400" do
    # 400.00 × 92.35% = 369.40 < 400 → 0. AGI 400.00 is under the standard deduction.
    result = worksheet({ 1 => 40_000 })
    expect(result.person_lines.first).to have_attributes(se_earnings_cents: 0, ss_cents: 0, medicare_cents: 0)
    expect(result.total_tax_cents).to eq(0)
  end

  it "works a $100,000 single-earner year line by line" do
    # SE earnings 92,350.00; SS 12.4% = 11,451.40; Medicare 2.9% = 2,678.15; half 7,064.775 → 7,064.78
    # AGI 100,000 − 7,064.78 = 92,935.22; before QBI 92,935.22 − 32,200 = 60,735.22
    # QBI 92,935.22; deduction 20% × min(92,935.22, 60,735.22) = 12,147.044 → 12,147.04; taxable 48,588.18
    # tax 2,480.00 + 12% × 23,788.18 (2,854.58) = 5,334.58; total 5,334.58 + 14,129.55 = 19,464.13
    result = worksheet({ 1 => 10_000_000 })
    expect(result.person_lines.first).to have_attributes(se_earnings_cents: 9_235_000, ss_cents: 1_145_140, medicare_cents: 267_815, half_se_cents: 706_478)
    expect(result).to have_attributes(agi_cents: 9_293_522, taxable_before_qbi_cents: 6_073_522, qbi_cents: 9_293_522, qbi_deduction_cents: 1_214_704,
                                      taxable_income_cents: 4_858_818, income_tax_cents: 533_458, additional_medicare_cents: 0)
    expect(result.bracket_slices.map(&:tax_cents)).to eq([ 248_000, 285_458 ])
    expect(result.se_tax_cents).to eq(1_412_955)
    expect(result.total_tax_cents).to eq(1_946_413)
  end

  it "caps Social Security at the wage base" do
    # $250,000: SE earnings 230,875.00; SS 12.4% × 184,500 = 22,878.00; Medicare 2.9% × 230,875 = 6,695.375 → 6,695.38
    result = worksheet({ 1 => 25_000_000 })
    expect(result.person_lines.first).to have_attributes(ss_cents: 2_287_800, medicare_cents: 669_538)
    expect(result.additional_medicare_cents).to eq(0)
    expect(result.total_tax_cents).to eq(5_472_772)
  end

  it "adds Additional Medicare on both spouses' combined SE earnings over $250,000" do
    # 2 × 184,700.00 = 369,400.00; 0.9% × 119,400.00 = 1,074.60
    result = worksheet({ 1 => 20_000_000, 2 => 20_000_000 })
    expect(result.person_lines.map(&:se_earnings_cents)).to eq([ 18_470_000, 18_470_000 ])
    expect(result.additional_medicare_cents).to eq(107_460)
    expect(result.total_tax_cents).to eq(10_793_581)
  end

  it "annualizes a Q2 period by 12/5" do
    # 50,000.00 × 2.4 = 120,000.00
    result = worksheet({ 1 => 5_000_000 }, quarter: 2)
    expect(result.business_lines.first).to have_attributes(ytd_cents: 5_000_000, annualized_cents: 12_000_000)
    expect(result.total_tax_cents).to eq(2_407_440)
  end

  it "annualizes a period in progress by days elapsed" do
    # Apr 20, 2026 is day 110: 22,000.00 × 365/110 = 73,000.00
    result = worksheet({ 1 => 2_200_000 }, quarter: 2, factor: Rational(365, 110), elapsed_days: 110)
    expect(result.business_lines.first.annualized_cents).to eq(7_300_000)
    expect(result.elapsed_days).to eq(110)
    expect(result.total_tax_cents).to eq(1_324_027)
  end

  it "caps the home office at profit and reports the carryover" do
    result = worksheet({ 1 => 100_000 }, businesses: [ tax_business(1, home_office_cents: 150_000) ])
    expect(result.business_lines.first).to have_attributes(home_office_used_cents: 100_000, carryover_cents: 50_000, net_profit_cents: 0)
    expect(result.total_tax_cents).to eq(0)
  end

  it "uses no home office against a loss and never makes SE tax negative" do
    result = worksheet({ 1 => -500_000 }, businesses: [ tax_business(1, home_office_cents: 150_000) ])
    expect(result.business_lines.first).to have_attributes(home_office_used_cents: 0, carryover_cents: 150_000, net_profit_cents: -500_000)
    expect(result.person_lines.first.se_earnings_cents).to eq(0)
    expect(result.total_tax_cents).to eq(0)
  end

  it "offsets a loss against the same person's other business, not the spouse's" do
    # Person 1: 30,000 − 10,000 = 20,000 → SE 18,470.00; person 2: 50,000 → SE 46,175.00
    businesses = [ tax_business(1, person_id: 1), tax_business(2, person_id: 1), tax_business(3, person_id: 2) ]
    result = worksheet({ 1 => 3_000_000, 2 => -1_000_000, 3 => 5_000_000 }, businesses:)
    expect(result.person_lines.map(&:net_profit_cents)).to eq([ 2_000_000, 5_000_000 ])
    expect(result.person_lines.map(&:se_earnings_cents)).to eq([ 1_847_000, 4_617_500 ])
    expect(result.total_tax_cents).to eq(1_254_874)
  end

  it "caps SE health insurance at profit less half SE tax and retirement" do
    # 10,000 profit: half SE 706.48; cap 10,000 − 706.48 = 9,293.52 of 15,000 entered; AGI 0
    result = worksheet({ 1 => 1_000_000 }, people: [ tax_person(1, health: 1_500_000) ])
    expect(result.person_lines.first.health_insurance_cents).to eq(929_352)
    expect(result.agi_cents).to eq(0)
    expect(result.total_tax_cents).to eq(141_296)
  end

  it "subtracts health insurance and retirement from AGI and QBI" do
    # 60,000 profit, half SE 4,238.87, health 9,000, SEP 10,000 → AGI 36,761.13; before QBI 4,561.13;
    # QBI deduction 20% × 4,561.13 = 912.226 → 912.23; taxable 3,648.90; tax 364.89; total 364.89 + 8,477.73
    result = worksheet({ 1 => 6_000_000 }, people: [ tax_person(1, health: 900_000, retirement: 1_000_000, plan: "sep") ])
    expect(result).to have_attributes(agi_cents: 3_676_113, qbi_deduction_cents: 91_223, taxable_income_cents: 364_890, income_tax_cents: 36_489)
    expect(result.total_tax_cents).to eq(884_262)
  end

  it "lists a person with no business with zero SE" do
    result = worksheet({ 1 => 10_000_000 }, people: [ tax_person(1), tax_person(2) ])
    expect(result.person_lines.last).to have_attributes(net_profit_cents: 0, se_earnings_cents: 0, half_se_cents: 0)
  end
end
```

- [ ] **Step 3: Run it to see it fail**

Run: `bundle exec rspec spec/models/tax/period_calculator_spec.rb`
Expected: FAIL (`uninitialized constant Tax::PeriodCalculator`).

- [ ] **Step 4: Structs, `to_tax_params`, worksheet, calculator**

One constant per file, so Zeitwerk can autoload each by name:

```ruby
# app/models/tax/business_input.rb
module Tax
  BusinessInput = Data.define(:id, :name, :person_id, :home_office_cents)
end

# app/models/tax/person_input.rb
module Tax
  PersonInput = Data.define(:id, :name, :se_health_insurance_cents, :retirement_contribution_cents, :retirement_plan)
end

# app/models/tax/period_input.rb
module Tax
  # elapsed_days is nil once the period has ended; profit_cents_by_business is YTD profit before home office.
  PeriodInput = Data.define(:quarter, :factor, :elapsed_days, :profit_cents_by_business)
end

# app/models/tax/prior_year.rb
module Tax
  PriorYear = Data.define(:total_tax_cents, :agi_cents)
end

# app/models/tax/payment.rb
module Tax
  Payment = Data.define(:quarter, :amount_cents)
end

# app/models/tax/inputs.rb
module Tax
  # Everything the estimator reads, as plain values.
  Inputs = Data.define(:year, :params, :businesses, :people, :periods, :prior_year, :payments, :today)
end
```

Add to `app/models/tax_parameters.rb` (public, under `estimate_ready?`):

```ruby
  def to_tax_params
    Tax::Params.new(
      standard_deduction_cents: standard_deduction_mfj_cents,
      brackets: brackets_mfj.map { Tax::Bracket.new(floor_cents: _1.fetch("floor_cents"), rate_bps: _1.fetch("rate_bps")) },
      ss_wage_base_cents:, se_earnings_bps:, ss_rate_bps:, medicare_rate_bps:, additional_medicare_bps:,
      additional_medicare_threshold_cents: additional_medicare_threshold_mfj_cents, qbi_bps:, qbi_threshold_cents: qbi_threshold_mfj_cents,
      home_office_rate_cents: home_office_simplified_rate_cents, home_office_max_sqft: home_office_simplified_max_sqft,
      safe_harbor_high_agi_threshold_cents:, annual_additions_limit_cents:, elective_deferral_limit_cents:
    )
  end
```

`app/models/tax/period_worksheet.rb`:

```ruby
module Tax
  # One Schedule AI period, every line of it. Amounts are annualized.
  PeriodWorksheet = Data.define(
    :quarter, :factor, :elapsed_days, :business_lines, :person_lines, :additional_medicare_cents, :total_net_profit_cents, :agi_cents,
    :standard_deduction_cents, :taxable_before_qbi_cents, :qbi_cents, :qbi_deduction_cents, :taxable_income_cents, :bracket_slices, :income_tax_cents
  ) do
    def se_tax_cents = person_lines.sum(&:se_tax_cents)
    def total_tax_cents = income_tax_cents + se_tax_cents + additional_medicare_cents
  end

  class PeriodWorksheet
    BusinessLine = Data.define(:business, :ytd_cents, :annualized_cents, :home_office_cents, :home_office_used_cents, :carryover_cents, :net_profit_cents)
    PersonLine = Data.define(:person, :net_profit_cents, :se_earnings_cents, :ss_cents, :medicare_cents, :half_se_cents, :retirement_cents, :health_insurance_cents) do
      def se_tax_cents = ss_cents + medicare_cents
    end
  end
end
```

`app/models/tax/period_calculator.rb`:

```ruby
module Tax
  # Parent spec §9.2 steps 1–5 for one Schedule AI period (tax engine spec §4.2).
  class PeriodCalculator
    SE_FLOOR_CENTS = 40_000

    def self.call(...) = new(...).worksheet

    def initialize(params:, businesses:, people:, period:)
      @params = params
      @businesses = businesses
      @people = people
      @period = period
    end

    def worksheet
      business_lines = @businesses.map { business_line(_1) }
      person_lines = @people.map { person_line(_1, business_lines) }
      total_net = business_lines.sum(&:net_profit_cents)
      agi = total_net - person_lines.sum { _1.half_se_cents + _1.health_insurance_cents + _1.retirement_cents }
      before_qbi = [ agi - @params.standard_deduction_cents, 0 ].max
      qbi = [ agi, 0 ].max
      qbi_deduction = rate(@params.qbi_bps, [ qbi, before_qbi ].min)
      taxable = before_qbi - qbi_deduction
      slices = Brackets.slices(taxable, @params.brackets)
      se_total = person_lines.sum(&:se_earnings_cents)

      PeriodWorksheet.new(
        quarter: @period.quarter, factor: @period.factor, elapsed_days: @period.elapsed_days, business_lines:, person_lines:,
        additional_medicare_cents: rate(@params.additional_medicare_bps, [ se_total - @params.additional_medicare_threshold_cents, 0 ].max),
        total_net_profit_cents: total_net, agi_cents: agi, standard_deduction_cents: @params.standard_deduction_cents,
        taxable_before_qbi_cents: before_qbi, qbi_cents: qbi, qbi_deduction_cents: qbi_deduction, taxable_income_cents: taxable,
        bracket_slices: slices, income_tax_cents: slices.sum(&:tax_cents)
      )
    end

    private

    def business_line(business)
      ytd = @period.profit_cents_by_business.fetch(business.id, 0)
      annualized = Money.round_rational(ytd * @period.factor.to_r)
      used = [ business.home_office_cents, [ annualized, 0 ].max ].min
      PeriodWorksheet::BusinessLine.new(business:, ytd_cents: ytd, annualized_cents: annualized, home_office_cents: business.home_office_cents,
                                        home_office_used_cents: used, carryover_cents: business.home_office_cents - used, net_profit_cents: annualized - used)
    end

    def person_line(person, business_lines)
      net = business_lines.select { _1.business.person_id == person.id }.sum(&:net_profit_cents)
      se_earnings = rate(@params.se_earnings_bps, [ net, 0 ].max)
      se_earnings = 0 if se_earnings < SE_FLOOR_CENTS
      ss = rate(@params.ss_rate_bps, [ se_earnings, @params.ss_wage_base_cents ].min)
      medicare = rate(@params.medicare_rate_bps, se_earnings)
      half = Money.round_rational(Rational(ss + medicare, 2))
      retirement = person.retirement_contribution_cents
      health = [ person.se_health_insurance_cents, [ net - half - retirement, 0 ].max ].min
      PeriodWorksheet::PersonLine.new(person:, net_profit_cents: net, se_earnings_cents: se_earnings, ss_cents: ss, medicare_cents: medicare,
                                      half_se_cents: half, retirement_cents: retirement, health_insurance_cents: health)
    end

    def rate(bps, cents) = Money.round_rational(Rational(cents * bps, 10_000))
  end
end
```

- [ ] **Step 5: Run, rubocop, commit**

Run: `bundle exec rspec spec/models/tax` → PASS; `bin/rubocop` clean.

```bash
git add app/models spec
git commit -m "Tax engine: per-period worksheet (SE tax, AGI, QBI, brackets)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Estimator — installments, safe harbor, warnings

**Files:**
- Create: `app/models/tax/estimate.rb`, `app/models/tax/estimator.rb`
- Test: `spec/models/tax/estimator_spec.rb`

**Interfaces:**
- Consumes: `Tax::Inputs` and the structs, `Tax::PeriodCalculator`, `Tax::DueDates` (Tasks 3–4).
- Produces:
  - `Tax::Estimator.new(inputs).estimate(quarter:) → Tax::Estimate`.
  - `Tax::Estimate` attributes `year quarter worksheets ninety_percent_cents safe_harbor_cents required_annual_cents installments warnings`; methods `worksheet` (the selected quarter's), `installment` (the selected quarter's), `next_due_on`, `pay_at_least_cents`.
  - `Tax::Estimate::Installment` (`quarter due_on regular_cents annualized_cents paid_cents paid_through_cents`, method `pay_at_least_cents`). `annualized_cents` is nil after the selected quarter.
  - `Tax::Estimate::Warning = Data.define(:kind, :message)`; kinds `:prior_year_missing`, `:qbi_threshold`, `:retirement_limit`, `:home_office_carryover`.

- [ ] **Step 1: Write the failing spec**

`spec/models/tax/estimator_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tax::Estimator do
  def estimate(quarter:, **inputs) = described_class.new(tax_inputs(**inputs)).estimate(quarter:)

  def rows(result) = result.installments.map { [ _1.regular_cents, _1.annualized_cents, _1.pay_at_least_cents ] }

  it "uses 90% of projected tax when that is below the safe harbor, and annualized wins early in a lumpy year" do
    # Periods annualize to 40,000 / 48,000 / 90,000: tax 6,049.75 / 7,774.89 / 17,159.00.
    # 90% × 17,159.00 = 15,443.10 < 30,000.00 safe harbor. Paid 2,000 in Q1 and Q2.
    # Regular: 15,443.10 × ¼ − 2,000 = 1,860.78; ×½ − 4,000 = 3,721.55; ×¾ − 4,000 = 7,582.33; ×1 − 4,000 = 11,443.10
    # Annualized: 22.5% × 6,049.75 − 2,000 → 0; 45% × 7,774.89 − 4,000 → 0; 67.5% × 17,159.00 − 4,000 = 7,582.33; Q4 —
    result = estimate(quarter: 3, ytd: { 1 => { 1 => 1_000_000 }, 2 => { 1 => 2_000_000 }, 3 => { 1 => 6_000_000 } },
                      prior_year: Tax::PriorYear.new(total_tax_cents: 3_000_000, agi_cents: 12_000_000),
                      payments: [ Tax::Payment.new(quarter: 1, amount_cents: 200_000), Tax::Payment.new(quarter: 2, amount_cents: 200_000) ])
    expect(result.worksheets.transform_values(&:total_tax_cents)).to eq(1 => 604_975, 2 => 777_489, 3 => 1_715_900)
    expect(result).to have_attributes(ninety_percent_cents: 1_544_310, safe_harbor_cents: 3_000_000, required_annual_cents: 1_544_310)
    expect(rows(result)).to eq([ [ 186_078, 0, 0 ], [ 372_155, 0, 0 ], [ 758_233, 758_233, 758_233 ], [ 1_144_310, nil, 1_144_310 ] ])
    expect(result.installments.map(&:paid_cents)).to eq([ 200_000, 200_000, 0, 0 ])
    expect(result.installments.map(&:paid_through_cents)).to eq([ 200_000, 400_000, 400_000, 400_000 ])
    expect(result.pay_at_least_cents).to eq(758_233)
    expect(result.next_due_on).to eq(Date.new(2026, 9, 15))
  end

  it "uses the 110% safe harbor when prior-year AGI is over $150,000, and regular wins" do
    # 110% × 10,000.00 = 11,000.00 < 90% × 24,074.40 = 21,666.96
    result = estimate(quarter: 2, ytd: { 1 => { 1 => 2_500_000 }, 2 => { 1 => 5_000_000 } },
                      prior_year: Tax::PriorYear.new(total_tax_cents: 1_000_000, agi_cents: 16_000_000))
    expect(result).to have_attributes(ninety_percent_cents: 2_166_696, safe_harbor_cents: 1_100_000, required_annual_cents: 1_100_000)
    expect(rows(result).first(2)).to eq([ [ 275_000, 437_943, 275_000 ], [ 550_000, 1_083_348, 550_000 ] ])
  end

  it "uses 100% at exactly $150,000 prior-year AGI" do
    result = estimate(quarter: 1, ytd: { 1 => { 1 => 2_500_000 } }, prior_year: Tax::PriorYear.new(total_tax_cents: 1_000_000, agi_cents: 15_000_000))
    expect(result.safe_harbor_cents).to eq(1_000_000)
  end

  it "skips the safe harbor and warns when the prior year is missing" do
    result = estimate(quarter: 1, ytd: { 1 => { 1 => 2_500_000 } })
    expect(result.safe_harbor_cents).to be_nil
    expect(result.required_annual_cents).to eq(1_751_772)
    expect(result.warnings.map(&:message)).to include("Enter last year's total tax and AGI to use the safe harbor.")
  end

  it "requires nothing after a year with no tax" do
    result = estimate(quarter: 1, ytd: { 1 => { 1 => 2_500_000 } }, prior_year: Tax::PriorYear.new(total_tax_cents: 0, agi_cents: 5_000_000))
    expect(result.required_annual_cents).to eq(0)
    expect(result.pay_at_least_cents).to eq(0)
  end

  it "floors every installment at zero when payments exceed the requirement" do
    result = estimate(quarter: 1, ytd: { 1 => { 1 => 2_500_000 } }, payments: [ Tax::Payment.new(quarter: 1, amount_cents: 5_000_000) ])
    expect(rows(result)).to eq([ [ 0, 0, 0 ], [ 0, nil, 0 ], [ 0, nil, 0 ], [ 0, nil, 0 ] ])
  end

  it "warns above the QBI threshold" do
    result = estimate(quarter: 4, ytd: { 4 => { 1 => 50_000_000 } })
    expect(result.worksheet.total_tax_cents).to eq(10_970_630)
    expect(result.warnings.map(&:message)).to include(
      "Taxable income is above the QBI threshold ($403,500.00); the simplified QBI deduction may be too high."
    )
  end

  it "warns when a SEP contribution is over 20% of profit less half SE tax" do
    # 60,000 profit: (60,000 − 4,238.87) × 20% = 11,152.226 → 11,152.23 limit; 12,000 entered
    result = estimate(quarter: 4, ytd: { 4 => { 1 => 6_000_000 } }, people: [ tax_person(1, retirement: 1_200_000, plan: "sep") ])
    expect(result.warnings.map(&:message)).to include("Person 1's SEP contribution ($12,000.00) is over the estimated limit ($11,152.23).")
  end

  it "allows a Solo 401(k) the elective deferral on top" do
    # limit min(72,000, 24,500 + 11,152.23) = 35,652.23
    result = estimate(quarter: 4, ytd: { 4 => { 1 => 6_000_000 } }, people: [ tax_person(1, retirement: 3_000_000, plan: "solo_401k") ])
    expect(result.warnings.map(&:kind)).not_to include(:retirement_limit)
  end

  it "warns about a home office carryover" do
    result = estimate(quarter: 4, ytd: { 4 => { 1 => 100_000 } }, businesses: [ tax_business(1, home_office_cents: 150_000) ])
    expect(result.warnings.map(&:message)).to include("Business 1's home office ($1,500.00) is more than its profit; $500.00 carries over.")
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/models/tax/estimator_spec.rb`
Expected: FAIL (`uninitialized constant Tax::Estimator`).

- [ ] **Step 3: Implement**

`app/models/tax/estimate.rb`:

```ruby
module Tax
  Estimate = Data.define(:year, :quarter, :worksheets, :ninety_percent_cents, :safe_harbor_cents, :required_annual_cents, :installments, :warnings) do
    def worksheet = worksheets.fetch(quarter)
    def installment = installments.fetch(quarter - 1)
    def next_due_on = installment.due_on
    def pay_at_least_cents = installment.pay_at_least_cents
  end

  class Estimate
    Warning = Data.define(:kind, :message)

    Installment = Data.define(:quarter, :due_on, :regular_cents, :annualized_cents, :paid_cents, :paid_through_cents) do
      def pay_at_least_cents = annualized_cents ? [ regular_cents, annualized_cents ].min : regular_cents
    end
  end
end
```

`app/models/tax/estimator.rb`:

```ruby
module Tax
  # Tax engine spec §4.3–4.4: runs each Schedule AI period up to the selected quarter, then the regular and annualized installments.
  class Estimator
    APPLICABLE_BPS = { 1 => 2_250, 2 => 4_500, 3 => 6_750, 4 => 9_000 }.freeze
    PLAN_NAMES = { "sep" => "SEP", "solo_401k" => "Solo 401(k)" }.freeze
    EMPLOYER_SHARE = Rational(1, 5) # 25% of compensation, which for the self-employed is 20% of profit less half SE tax

    def initialize(inputs)
      @inputs = inputs
      @params = inputs.params
    end

    def estimate(quarter:)
      worksheets = @inputs.periods.select { _1.quarter <= quarter }.sort_by(&:quarter).to_h do |period|
        [ period.quarter, PeriodCalculator.call(params: @params, businesses: @inputs.businesses, people: @inputs.people, period:) ]
      end
      ninety = Money.round_rational(Rational(worksheets.fetch(quarter).total_tax_cents * 9, 10))
      safe_harbor = safe_harbor_cents
      required = safe_harbor ? [ ninety, safe_harbor ].min : ninety

      Estimate.new(year: @inputs.year, quarter:, worksheets:, ninety_percent_cents: ninety, safe_harbor_cents: safe_harbor,
                   required_annual_cents: required, installments: installments(worksheets, required),
                   warnings: warnings(worksheets.fetch(quarter)))
    end

    private

    def safe_harbor_cents
      prior = @inputs.prior_year
      return unless prior

      percent = prior.agi_cents > @params.safe_harbor_high_agi_threshold_cents ? 110 : 100
      Money.round_rational(Rational(prior.total_tax_cents * percent, 100))
    end

    def installments(worksheets, required)
      DueDates.for(@inputs.year).each_with_index.map do |due_on, index|
        quarter = index + 1
        paid_through = @inputs.payments.select { _1.quarter <= quarter }.sum(&:amount_cents)
        annualized = worksheets[quarter] &&
          [ Money.round_rational(Rational(worksheets[quarter].total_tax_cents * APPLICABLE_BPS.fetch(quarter), 10_000)) - paid_through, 0 ].max
        Estimate::Installment.new(
          quarter:, due_on:, annualized_cents: annualized, paid_through_cents: paid_through,
          regular_cents: [ Money.round_rational(Rational(required * quarter, 4)) - paid_through, 0 ].max,
          paid_cents: @inputs.payments.select { _1.quarter == quarter }.sum(&:amount_cents)
        )
      end
    end

    def warnings(worksheet)
      list = []
      list << Estimate::Warning.new(kind: :prior_year_missing, message: "Enter last year's total tax and AGI to use the safe harbor.") unless @inputs.prior_year
      if worksheet.taxable_before_qbi_cents > @params.qbi_threshold_cents
        list << Estimate::Warning.new(kind: :qbi_threshold, message: "Taxable income is above the QBI threshold (#{Money.new(@params.qbi_threshold_cents)}); " \
                                                                     "the simplified QBI deduction may be too high.")
      end
      worksheet.person_lines.each { |line| list << retirement_warning(line) }
      worksheet.business_lines.select { _1.carryover_cents.positive? }.each do |line|
        list << Estimate::Warning.new(kind: :home_office_carryover, message: "#{line.business.name}'s home office (#{Money.new(line.home_office_cents)}) " \
                                                                             "is more than its profit; #{Money.new(line.carryover_cents)} carries over.")
      end
      list.compact
    end

    def retirement_warning(line)
      person = line.person
      return unless person.retirement_contribution_cents.positive? && PLAN_NAMES.key?(person.retirement_plan)

      employer = Money.round_rational([ line.net_profit_cents - line.half_se_cents, 0 ].max * EMPLOYER_SHARE)
      employer += @params.elective_deferral_limit_cents if person.retirement_plan == "solo_401k"
      limit = [ @params.annual_additions_limit_cents, employer ].min
      return if person.retirement_contribution_cents <= limit

      Estimate::Warning.new(kind: :retirement_limit, message: "#{person.name}'s #{PLAN_NAMES.fetch(person.retirement_plan)} contribution " \
                                                              "(#{Money.new(person.retirement_contribution_cents)}) is over the estimated limit (#{Money.new(limit)}).")
    end
  end
end
```

`Money#to_s` gives `$403,500.00`, which the messages use.

- [ ] **Step 4: Run, rubocop, commit**

Run: `bundle exec rspec spec/models/tax` → PASS; `bin/rubocop` clean.

```bash
git add app/models/tax spec/models/tax
git commit -m "Tax engine: estimator with regular and annualized installments, safe harbor, warnings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 6: Tax records — household URL, tax years, payments, home offices, adjustments

**Files:**
- Create: `db/migrate/20261012000002_create_tax_records.rb`, `app/models/tax_year.rb`, `app/models/estimated_payment.rb`, `app/models/home_office.rb`, `app/models/person_adjustment.rb`, `spec/factories/tax_years.rb`, `spec/factories/estimated_payments.rb`, `spec/factories/home_offices.rb`, `spec/factories/person_adjustments.rb`
- Modify: `app/models/household.rb`, `app/models/person.rb`, `app/models/business.rb`, `app/models/transaction.rb`
- Test: `spec/models/tax_year_spec.rb`, `spec/models/estimated_payment_spec.rb`, `spec/models/home_office_spec.rb`, `spec/models/person_adjustment_spec.rb`, `spec/models/household_spec.rb`

**Interfaces:**
- Consumes: `Tax::DueDates.quarter_on`, `Tax::HomeOfficeDeduction.cents`, `Tax::PriorYear` (Tasks 3–4).
- Produces:
  - `Household#irs_payment_url`, `Household::DEFAULT_IRS_PAYMENT_URL`, `Household has_many :tax_years`.
  - `TaxYear.for(household, year) → TaxYear` (find or create), `TaxYear#prior_year → Tax::PriorYear | nil`, money attributes `prior_year_total_tax`, `prior_year_agi`.
  - `EstimatedPayment` (`tax_year`, `debit` → `Transaction`, `quarter`, `paid_on`, money attribute `amount`), `EstimatedPayment#link(debit)`.
  - `Transaction has_one :estimated_payment` (via `debit_id`, nullify).
  - `HomeOffice` (`business`, `year`, `calculation`, sq ft, cost money attributes named without `_cents`), `HomeOffice::COSTS`, `HomeOffice::CALCULATIONS`, `HomeOffice#deduction_cents(tax_parameters) → Integer | nil`. `Business has_many :home_offices`.
  - `PersonAdjustment` (`person`, `year`, money attributes `se_health_insurance`, `retirement_contribution`, `retirement_plan`), `PersonAdjustment::PLANS`. `Person has_many :person_adjustments`.

- [ ] **Step 1: Write the failing model specs**

`spec/models/tax_year_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe TaxYear do
  let(:household) { create(:household) }

  it "finds or creates the year's row" do
    first = described_class.for(household, 2026)
    expect(described_class.for(household, 2026)).to eq(first)
    expect(described_class.count).to eq(1)
  end

  it "gives a prior year only when both figures are present" do
    expect(build(:tax_year, household:, prior_year_total_tax_cents: 100).prior_year).to be_nil
    expect(build(:tax_year, household:, prior_year_total_tax_cents: 100, prior_year_agi_cents: -500).prior_year)
      .to eq(Tax::PriorYear.new(total_tax_cents: 100, agi_cents: -500))
  end

  it "takes money text, allows a negative AGI, and rejects negative tax" do
    year = build(:tax_year, household:, prior_year_total_tax: "24,000", prior_year_agi: "-1,500.50")
    expect(year).to be_valid
    expect(year.prior_year_agi_cents).to eq(-150_050)
    expect(build(:tax_year, household:, prior_year_total_tax: "-1")).not_to be_valid
  end

  it "rejects a year outside 2000–2100" do
    expect(build(:tax_year, household:, year: 1999)).not_to be_valid
  end
end
```

`spec/models/estimated_payment_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe EstimatedPayment do
  let(:tax_year) { create(:tax_year, year: 2026) }
  let(:debit) { create(:transaction, posted_on: Date.new(2026, 6, 12), amount_cents: -450_000, payee: "IRS USATAXPYMT") }

  it "takes amount, date, and a default quarter from the linked debit" do
    payment = tax_year.estimated_payments.new
    payment.link(debit)
    payment.save!
    expect(payment).to have_attributes(amount_cents: 450_000, paid_on: Date.new(2026, 6, 12), quarter: 2, debit:)
  end

  it "defaults a January payment to Q4" do
    payment = tax_year.estimated_payments.create!(paid_on: Date.new(2027, 1, 10), amount: "1,000")
    expect(payment.quarter).to eq(4)
  end

  it "keeps a quarter chosen by hand" do
    expect(tax_year.estimated_payments.create!(paid_on: Date.new(2026, 4, 15), amount: "500", quarter: 2).quarter).to eq(2)
  end

  it "refuses money in" do
    payment = tax_year.estimated_payments.new
    payment.link(create(:transaction, amount_cents: 1_000))
    expect(payment).not_to be_valid
    expect(payment.errors[:debit]).to include("must be money paid out")
  end

  it "refuses a debit already recorded" do
    tax_year.estimated_payments.new.tap { _1.link(debit) }.save!
    second = tax_year.estimated_payments.new.tap { _1.link(debit) }
    expect(second).not_to be_valid
    expect(second.errors[:debit_id]).to include("is already recorded as a payment")
  end

  it "keeps the payment as a manual one when the debit is deleted" do
    payment = tax_year.estimated_payments.new.tap { _1.link(debit) }
    payment.save!
    debit.destroy!
    expect(payment.reload.debit_id).to be_nil
    expect(payment.amount_cents).to eq(450_000)
  end

  it "requires a positive amount and a date" do
    expect(tax_year.estimated_payments.new(paid_on: Date.new(2026, 4, 1), amount: "0")).not_to be_valid
    expect(tax_year.estimated_payments.new(amount: "10")).not_to be_valid
  end
end
```

`spec/models/home_office_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe HomeOffice do
  let(:business) { create(:business) }

  it "defaults blank costs to zero" do
    office = described_class.create!(business:, year: 2026, calculation: "simplified", office_sqft: 200, rent: "")
    expect(office.rent_cents).to eq(0)
  end

  it "requires a home size at least the office size for the regular method" do
    expect(build(:home_office, business:, calculation: "regular", home_sqft: nil)).not_to be_valid
    office = build(:home_office, business:, calculation: "regular", office_sqft: 300, home_sqft: 200)
    expect(office).not_to be_valid
    expect(office.errors[:home_sqft]).to eq([ "must be at least the office's square feet" ])
  end

  it "rejects the personal book" do
    office = build(:home_office, business: create(:business, :personal))
    expect(office).not_to be_valid
    expect(office.errors[:business]).to eq([ "must be a business, not the personal book" ])
  end

  it "rejects negative costs" do
    expect(build(:home_office, business:, utilities: "-5")).not_to be_valid
  end

  it "computes its deduction from the year's parameters" do
    params = build(:tax_parameters, :federal_2026)
    expect(build(:home_office, business:, office_sqft: 200).deduction_cents(params)).to eq(100_000)
    regular = build(:home_office, business:, calculation: "regular", office_sqft: 200, home_sqft: 2_000, rent: "24,000")
    expect(regular.deduction_cents(nil)).to eq(240_000)
  end

  it "has no simplified deduction without a rate" do
    expect(build(:home_office, business:).deduction_cents(nil)).to be_nil
  end
end
```

`spec/models/person_adjustment_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PersonAdjustment do
  let(:person) { create(:person) }

  it "defaults blank amounts to zero" do
    adjustment = described_class.create!(person:, year: 2026, se_health_insurance: "", retirement_contribution: "")
    expect(adjustment).to have_attributes(se_health_insurance_cents: 0, retirement_contribution_cents: 0, retirement_plan: nil)
  end

  it "requires a plan with a contribution" do
    adjustment = build(:person_adjustment, person:, retirement_contribution: "6,000", retirement_plan: "")
    expect(adjustment).not_to be_valid
    expect(adjustment.errors[:retirement_plan]).to eq([ "is required with a contribution" ])
  end

  it "accepts only known plans" do
    expect(build(:person_adjustment, person:, retirement_contribution: "1", retirement_plan: "ira")).not_to be_valid
  end

  it "is unique per person and year" do
    create(:person_adjustment, person:, year: 2026)
    expect(build(:person_adjustment, person:, year: 2026)).not_to be_valid
  end
end
```

Append to `spec/models/household_spec.rb` (inside its `describe`):

```ruby
  it "defaults the IRS payment URL to Direct Pay and requires https" do
    household = create(:household)
    expect(household.irs_payment_url).to eq("https://www.irs.gov/payments/direct-pay")
    household.irs_payment_url = "http://example.com"
    expect(household).not_to be_valid
    household.irs_payment_url = "javascript:alert(1)"
    expect(household).not_to be_valid
    household.irs_payment_url = "https://www.irs.gov/payments"
    expect(household).to be_valid
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/tax_year_spec.rb spec/models/estimated_payment_spec.rb spec/models/home_office_spec.rb spec/models/person_adjustment_spec.rb spec/models/household_spec.rb`
Expected: FAIL (missing tables and models).

- [ ] **Step 3: Migration**

`db/migrate/20261012000002_create_tax_records.rb`:

```ruby
class CreateTaxRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :irs_payment_url, :string, null: false, default: "https://www.irs.gov/payments/direct-pay"

    create_table :tax_years do |t|
      t.references :household, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :prior_year_total_tax_cents
      t.integer :prior_year_agi_cents
      t.timestamps
    end
    add_index :tax_years, %i[household_id year], unique: true

    create_table :estimated_payments do |t|
      t.references :tax_year, null: false, foreign_key: true
      t.integer :quarter, null: false
      t.date :paid_on, null: false
      t.integer :amount_cents, null: false
      t.references :debit, foreign_key: { to_table: :transactions, on_delete: :nullify }, index: { unique: true }
      t.timestamps
    end

    create_table :home_offices do |t|
      t.references :business, null: false, foreign_key: true
      t.integer :year, null: false
      t.string :calculation, null: false, default: "simplified"
      t.integer :office_sqft, null: false
      t.integer :home_sqft
      t.integer :rent_cents, null: false, default: 0
      t.integer :mortgage_interest_cents, null: false, default: 0
      t.integer :utilities_cents, null: false, default: 0
      t.integer :insurance_cents, null: false, default: 0
      t.integer :repairs_cents, null: false, default: 0
      t.integer :other_cents, null: false, default: 0
      t.integer :depreciation_cents, null: false, default: 0
      t.timestamps
    end
    add_index :home_offices, %i[business_id year], unique: true

    create_table :person_adjustments do |t|
      t.references :person, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :se_health_insurance_cents, null: false, default: 0
      t.integer :retirement_contribution_cents, null: false, default: 0
      t.string :retirement_plan
      t.timestamps
    end
    add_index :person_adjustments, %i[person_id year], unique: true
  end
end
```

Run: `bin/rails db:migrate`.

- [ ] **Step 4: Models**

`app/models/household.rb` — add:

```ruby
  DEFAULT_IRS_PAYMENT_URL = "https://www.irs.gov/payments/direct-pay".freeze

  has_many :tax_years, dependent: :destroy

  validates :irs_payment_url, format: { with: %r{\Ahttps://[a-z0-9.-]+\.[a-z]{2,}(/\S*)?\z}i, message: "must be an https:// web address" }
```

`app/models/person.rb` — add `has_many :person_adjustments, dependent: :destroy`.
`app/models/business.rb` — add `has_many :home_offices, dependent: :destroy`.
`app/models/transaction.rb` — under `has_many :invoice_payments`, add `has_one :estimated_payment, foreign_key: :debit_id, inverse_of: :debit, dependent: :nullify`.

`app/models/tax_year.rb`:

```ruby
class TaxYear < ApplicationRecord
  include MoneyAttribute

  belongs_to :household
  has_many :estimated_payments, dependent: :destroy

  money_attribute :prior_year_total_tax, allow_blank: true
  money_attribute :prior_year_agi, allow_blank: true

  validates :year, numericality: { only_integer: true, in: 2000..2100 }, uniqueness: { scope: :household_id }
  validates :prior_year_total_tax_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def self.for(household, year) = household.tax_years.find_or_create_by!(year: year)

  def prior_year
    return unless prior_year_total_tax_cents && prior_year_agi_cents

    Tax::PriorYear.new(total_tax_cents: prior_year_total_tax_cents, agi_cents: prior_year_agi_cents)
  end
end
```

`app/models/estimated_payment.rb`:

```ruby
class EstimatedPayment < ApplicationRecord
  include MoneyAttribute

  belongs_to :tax_year
  belongs_to :debit, class_name: "Transaction", optional: true, inverse_of: :estimated_payment

  money_attribute :amount

  before_validation :default_quarter

  validates :quarter, inclusion: { in: 1..4 }
  validates :paid_on, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :debit_id, uniqueness: { message: "is already recorded as a payment" }, allow_nil: true
  validate :debit_is_money_out

  def link(debit)
    self.debit = debit
    self.amount_cents = -debit.amount_cents
    self.paid_on = debit.posted_on
  end

  private

  def default_quarter
    self.quarter = nil if quarter.blank?
    self.quarter ||= Tax::DueDates.quarter_on(tax_year.year, paid_on) if tax_year && paid_on
  end

  def debit_is_money_out
    errors.add(:debit, "must be money paid out") if debit && debit.amount_cents >= 0
  end
end
```

`app/models/home_office.rb`:

```ruby
class HomeOffice < ApplicationRecord
  include MoneyAttribute

  CALCULATIONS = %w[simplified regular].freeze
  COSTS = %i[rent mortgage_interest utilities insurance repairs other depreciation].freeze

  belongs_to :business

  COSTS.each { money_attribute _1, allow_blank: true }

  before_validation { COSTS.each { |cost| self[:"#{cost}_cents"] ||= 0 } }

  validates :year, numericality: { only_integer: true, in: 2000..2100 }, uniqueness: { scope: :business_id }
  validates :calculation, inclusion: { in: CALCULATIONS }
  validates :office_sqft, numericality: { only_integer: true, greater_than: 0 }
  validate :home_sqft_covers_office
  validate :business_kind_only
  validate :costs_not_negative

  def regular? = calculation == "regular"

  # Uncapped; nil for the simplified method when the year has no rate.
  def deduction_cents(tax_parameters)
    rate = tax_parameters&.home_office_simplified_rate_cents
    max_sqft = tax_parameters&.home_office_simplified_max_sqft
    return if !regular? && (rate.nil? || max_sqft.nil?)

    Tax::HomeOfficeDeduction.cents(self, rate_cents: rate.to_i, max_sqft: max_sqft.to_i)
  end

  private

  def home_sqft_covers_office
    return unless regular?

    if home_sqft.blank? then errors.add(:home_sqft, "is required for the regular method")
    elsif !home_sqft.to_i.positive? then errors.add(:home_sqft, "must be greater than 0")
    elsif office_sqft && home_sqft < office_sqft then errors.add(:home_sqft, "must be at least the office's square feet")
    end
  end

  def business_kind_only
    errors.add(:business, "must be a business, not the personal book") if business&.personal?
  end

  def costs_not_negative
    COSTS.each { |cost| errors.add(cost, "can't be negative") if self[:"#{cost}_cents"].to_i.negative? }
  end
end
```

`app/models/person_adjustment.rb`:

```ruby
class PersonAdjustment < ApplicationRecord
  include MoneyAttribute

  PLANS = { "sep" => "SEP-IRA", "solo_401k" => "Solo 401(k)" }.freeze

  belongs_to :person

  money_attribute :se_health_insurance, allow_blank: true
  money_attribute :retirement_contribution, allow_blank: true

  before_validation do
    self.se_health_insurance_cents ||= 0
    self.retirement_contribution_cents ||= 0
    self.retirement_plan = nil if retirement_plan.blank?
  end

  validates :year, numericality: { only_integer: true, in: 2000..2100 }, uniqueness: { scope: :person_id }
  validates :retirement_plan, inclusion: { in: PLANS.keys }, allow_nil: true
  validates :retirement_plan, presence: { message: "is required with a contribution" }, if: -> { retirement_contribution_cents.to_i.positive? }
  validates :se_health_insurance_cents, :retirement_contribution_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
```

- [ ] **Step 5: Factories**

```ruby
# spec/factories/tax_years.rb
FactoryBot.define do
  factory :tax_year do
    household { Household.first || association(:household) }
    year { 2026 }
  end
end

# spec/factories/estimated_payments.rb
FactoryBot.define do
  factory :estimated_payment do
    tax_year
    paid_on { Date.new(2026, 4, 15) }
    amount_cents { 100_000 }
  end
end

# spec/factories/home_offices.rb
FactoryBot.define do
  factory :home_office do
    business
    year { 2026 }
    calculation { "simplified" }
    office_sqft { 200 }
  end
end

# spec/factories/person_adjustments.rb
FactoryBot.define do
  factory :person_adjustment do
    person
    year { 2026 }
  end
end
```

- [ ] **Step 6: Run, rubocop, commit**

Run: `bundle exec rspec spec/models` → PASS; then `bundle exec rspec` and `bin/rubocop` → clean.

```bash
git add app/models db spec
git commit -m "Tax engine: tax years, estimated payments, home offices, adjustments, IRS payment URL

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Loading inputs, `Tax.estimate`, Schedule C home office split

**Files:**
- Create: `app/models/tax.rb`, `spec/models/tax/inputs_spec.rb`, `spec/models/tax_spec.rb`
- Modify: `app/models/tax/inputs.rb`, `app/models/reports/schedule_c_summary.rb`, `spec/models/reports/schedule_c_summary_spec.rb` (create it if it doesn't exist)

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces:
  - `Tax::Inputs.load(household:, year:, tax_parameters:, today: Date.current) → Tax::Inputs`.
  - `Tax.estimate(household:, year:, today: Date.current, quarter: nil) → Tax::Estimate | nil` (nil when the year's parameters aren't `estimate_ready?`).
  - `Tax.default_quarter(year, today) → 1..4` (1 for a year that hasn't started).
  - `Reports::ScheduleCSummary.new(category_totals:, mileage_deduction_cents:, home_office_cents: nil)`, `#tentative_profit_cents`, `#home_office_used_cents → Integer | nil`, `#net_profit_cents` (tentative − home office used).

- [ ] **Step 1: Write the failing specs**

`spec/models/reports/schedule_c_summary_spec.rb` (add these examples to the existing file if there is one):

```ruby
require "rails_helper"

RSpec.describe Reports::ScheduleCSummary do
  let(:totals) { [ Reports::CategoryTotal.new(business_id: 1, category_id: 1, name: "Sales", kind: "income", schedule_c_line: "1", deductible_bps: 10_000, sum_cents: 100_000) ] }

  it "subtracts the home office after tentative profit" do
    summary = described_class.new(category_totals: totals, mileage_deduction_cents: 0, home_office_cents: 30_000)
    expect(summary).to have_attributes(tentative_profit_cents: 100_000, home_office_used_cents: 30_000, net_profit_cents: 70_000)
  end

  it "caps the home office at tentative profit" do
    summary = described_class.new(category_totals: totals, mileage_deduction_cents: 0, home_office_cents: 150_000)
    expect(summary).to have_attributes(home_office_used_cents: 100_000, net_profit_cents: 0)
  end

  it "has no line 30 without a home office" do
    summary = described_class.new(category_totals: totals, mileage_deduction_cents: 0)
    expect(summary.home_office_used_cents).to be_nil
    expect(summary.net_profit_cents).to eq(100_000)
  end
end
```

`spec/models/tax/inputs_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tax::Inputs do
  let!(:household) { create(:household) }
  let(:person) { create(:person, household:) }
  let(:business) { create(:business, household:, person:) }
  let(:account) { create(:account, business:) }
  let(:income) { create(:category, :income, business:) }
  let(:tax_parameters) { create(:tax_parameters, :federal_2026) }

  def load(today) = described_class.load(household:, year: 2026, tax_parameters:, today:)

  def deposit(on, cents, category: income, to: account) = create(:transaction, account: to, category:, posted_on: on, amount_cents: cents)

  it "takes YTD profit for each ended period with the Schedule AI factors" do
    deposit(Date.new(2026, 3, 31), 100_000)
    deposit(Date.new(2026, 4, 1), 50_000)
    deposit(Date.new(2026, 9, 1), 7_000)
    inputs = load(Date.new(2026, 9, 1))
    expect(inputs.periods.first(3).map { _1.profit_cents_by_business[business.id] }).to eq([ 100_000, 150_000, 150_000 ])
    expect(inputs.periods.first(3).map(&:factor)).to eq([ 4, Rational(12, 5), Rational(3, 2) ])
    expect(inputs.periods.first(3).map(&:elapsed_days)).to eq([ nil, nil, nil ])
  end

  it "projects a period in progress from the days elapsed" do
    deposit(Date.new(2026, 4, 20), 100_000)
    q4 = load(Date.new(2026, 9, 1)).periods.last
    expect(q4).to have_attributes(elapsed_days: 244, factor: Rational(365, 244)) # Sep 1 is day 244 of 2026
    expect(q4.profit_cents_by_business[business.id]).to eq(100_000)
  end

  it "has no data and a factor of 1 for a year that hasn't started" do
    deposit(Date.new(2026, 1, 5), 100_000)
    inputs = load(Date.new(2025, 12, 1))
    expect(inputs.periods.map(&:factor)).to eq([ 1, 1, 1, 1 ])
    expect(inputs.periods.map(&:profit_cents_by_business)).to all(eq({}))
  end

  it "subtracts mileage and nets collected sales tax" do
    create(:sales_tax_profile, business:)
    taxable = create(:category, :income, business:, sales_tax_treatment: "taxable")
    create(:transaction, account:, category: taxable, posted_on: Date.new(2026, 2, 1), amount_cents: 10_925, sales_tax_cents: 925)
    create(:mileage_entry, business:, driven_on: Date.new(2026, 3, 2), miles_tenths: 100) # 10 miles × 72.5¢ = $7.25
    expect(load(Date.new(2026, 4, 1)).periods.first.profit_cents_by_business[business.id]).to eq(10_000 - 725)
  end

  it "leaves out the personal book and keeps archived businesses" do
    personal = create(:business, :personal, household:)
    deposit(Date.new(2026, 2, 1), 999_999, category: create(:category, :income, business: personal), to: create(:account, business: personal))
    business.update!(archived_at: Time.current)
    inputs = load(Date.new(2026, 4, 1))
    expect(inputs.businesses.map(&:id)).to eq([ business.id ])
    expect(inputs.periods.first.profit_cents_by_business.keys).to eq([ business.id ])
  end

  it "maps home offices, adjustments, the prior year, and payments" do
    create(:home_office, business:, office_sqft: 200)
    create(:person_adjustment, person:, se_health_insurance_cents: 720_000, retirement_contribution_cents: 600_000, retirement_plan: "sep")
    tax_year = create(:tax_year, household:, prior_year_total_tax_cents: 2_400_000, prior_year_agi_cents: 11_800_000)
    create(:estimated_payment, tax_year:, quarter: 1, amount_cents: 450_000)
    inputs = load(Date.new(2026, 4, 1))
    expect(inputs.businesses.first).to have_attributes(person_id: person.id, home_office_cents: 100_000)
    expect(inputs.people.first).to have_attributes(se_health_insurance_cents: 720_000, retirement_contribution_cents: 600_000, retirement_plan: "sep")
    expect(inputs.prior_year).to eq(Tax::PriorYear.new(total_tax_cents: 2_400_000, agi_cents: 11_800_000))
    expect(inputs.payments).to eq([ Tax::Payment.new(quarter: 1, amount_cents: 450_000) ])
  end

  it "gives people without adjustments zeros" do
    person
    expect(load(Date.new(2026, 4, 1)).people.first).to have_attributes(se_health_insurance_cents: 0, retirement_contribution_cents: 0, retirement_plan: nil)
  end
end
```

`spec/models/tax_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tax do
  let!(:household) { create(:household) }

  it "is nil without estimate-ready parameters" do
    expect(described_class.estimate(household:, year: 2026)).to be_nil
    create(:tax_parameters, year: 2026)
    expect(described_class.estimate(household:, year: 2026)).to be_nil
  end

  it "estimates the current installment by default" do
    create(:tax_parameters, :federal_2026)
    estimate = described_class.estimate(household:, year: 2026, today: Date.new(2026, 5, 1))
    expect(estimate.quarter).to eq(2)
    expect(estimate.next_due_on).to eq(Date.new(2026, 6, 15))
  end

  it "picks Q1 for a year that hasn't started and Q4 for one that has ended" do
    expect(described_class.default_quarter(2027, Date.new(2026, 10, 12))).to eq(1)
    expect(described_class.default_quarter(2025, Date.new(2026, 10, 12))).to eq(4)
  end
end
```

Check the `sales_tax_treatment` attribute name against `app/models/category.rb` before running; the sales tax plan's Task 1 added it.

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/reports/schedule_c_summary_spec.rb spec/models/tax/inputs_spec.rb spec/models/tax_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Schedule C summary**

In `app/models/reports/schedule_c_summary.rb`, change the constructor and the bottom three methods:

```ruby
    def initialize(category_totals:, mileage_deduction_cents:, home_office_cents: nil)
      @pnl = ProfitAndLoss.new(category_totals:, mileage_deduction_cents:)
      @home_office_cents = home_office_cents
    end
```

```ruby
    def gross_income_cents = lines.fetch("1", 0) - lines.fetch("2", 0) + lines.fetch("6", 0)
    def total_expenses_cents = lines.except(*ScheduleC::INCOME_LINES).values.sum
    def tentative_profit_cents = gross_income_cents - total_expenses_cents

    # Line 30, capped so the home office never creates a loss.
    def home_office_used_cents
      @home_office_cents && [ @home_office_cents, [ tentative_profit_cents, 0 ].max ].min
    end

    def net_profit_cents = tentative_profit_cents - home_office_used_cents.to_i
```

- [ ] **Step 4: `Tax::Inputs.load` and `Tax.estimate`**

Append to `app/models/tax/inputs.rb` (inside `module Tax`, after the `Inputs = Data.define(...)` line):

```ruby
  class Inputs
    PERIOD_END_MONTHS = { 1 => 3, 2 => 5, 3 => 8, 4 => 12 }.freeze
    FACTORS = { 1 => 4, 2 => Rational(12, 5), 3 => Rational(3, 2), 4 => 1 }.freeze

    def self.load(household:, year:, tax_parameters:, today: Date.current)
      books = household.businesses.business_kind.order(:name).to_a
      ids = books.map(&:id)
      home_offices = HomeOffice.where(business_id: ids, year:).index_by(&:business_id)
      adjustments = PersonAdjustment.where(person_id: household.people.select(:id), year:).index_by(&:person_id)
      tax_year = household.tax_years.includes(:estimated_payments).find_by(year:)
      profits = Hash.new { |cache, range| cache[range] = profits_for(ids, range) }

      new(
        year:, today:, params: tax_parameters.to_tax_params,
        businesses: books.map do |book|
          BusinessInput.new(id: book.id, name: book.name, person_id: book.person_id,
                            home_office_cents: home_offices[book.id]&.deduction_cents(tax_parameters) || 0)
        end,
        people: household.people.order(:name).map { person_input(_1, adjustments[_1.id]) },
        periods: (1..4).map { period_input(_1, year, today, profits) },
        prior_year: tax_year&.prior_year,
        payments: tax_year ? tax_year.estimated_payments.map { Payment.new(quarter: _1.quarter, amount_cents: _1.amount_cents) } : []
      )
    end

    def self.person_input(person, adjustment)
      PersonInput.new(id: person.id, name: person.name, se_health_insurance_cents: adjustment&.se_health_insurance_cents || 0,
                      retirement_contribution_cents: adjustment&.retirement_contribution_cents || 0, retirement_plan: adjustment&.retirement_plan)
    end

    def self.period_input(quarter, year, today, profits)
      starts_on = Date.new(year)
      ends_on = Date.new(year, PERIOD_END_MONTHS.fetch(quarter)).end_of_month
      if ends_on <= today
        PeriodInput.new(quarter:, factor: FACTORS.fetch(quarter), elapsed_days: nil, profit_cents_by_business: profits[starts_on..ends_on])
      elsif today < starts_on
        PeriodInput.new(quarter:, factor: 1, elapsed_days: 0, profit_cents_by_business: {})
      else
        elapsed = (today - starts_on).to_i + 1
        PeriodInput.new(quarter:, factor: Rational(starts_on.end_of_year.yday, elapsed), elapsed_days: elapsed, profit_cents_by_business: profits[starts_on..today])
      end
    end

    def self.profits_for(ids, range)
      totals = Reports::CategoryTotals.load(business_ids: ids, range:).group_by(&:business_id)
      ids.index_with do |id|
        mileage = Reports::MileageTotals.load(business_ids: [ id ], range:).deduction_cents
        Reports::ScheduleCSummary.new(category_totals: totals.fetch(id, []), mileage_deduction_cents: mileage).tentative_profit_cents
      end
    end

    private_class_method :person_input, :period_input, :profits_for
  end
```

`app/models/tax.rb`:

```ruby
# Federal estimated tax (tax engine spec). Everything is derived on each call; nothing is stored.
module Tax
  def self.estimate(household:, year:, today: Date.current, quarter: nil)
    tax_parameters = TaxParameters.for_year(year)
    return unless tax_parameters&.estimate_ready?

    inputs = Inputs.load(household:, year:, tax_parameters:, today:)
    Estimator.new(inputs).estimate(quarter: quarter || default_quarter(year, today))
  end

  def self.default_quarter(year, today) = today < Date.new(year) ? 1 : DueDates.quarter_on(year, today)
end
```

- [ ] **Step 5: Run, rubocop, commit**

Run: `bundle exec rspec spec/models` → PASS. Run `bundle exec rspec spec/requests/reports_spec.rb` too: the Schedule C view still calls `net_profit_cents`, which is unchanged without a home office. `bin/rubocop` clean.

```bash
git add app/models spec
git commit -m "Tax engine: load inputs from the books, Tax.estimate, Schedule C line 30 math

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Household settings page

**Files:**
- Create: `app/controllers/households_controller.rb`, `app/views/households/edit.html.erb`, `spec/requests/households_spec.rb`
- Modify: `config/routes.rb`, `app/helpers/navigation_helper.rb`, `spec/requests/navigation_spec.rb`

**Interfaces:**
- Consumes: `Household#irs_payment_url` (Task 6).
- Produces: `edit_household_path`, `household_path` (PATCH).

- [ ] **Step 1: Write the failing request spec**

`spec/requests/households_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Household settings" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }

  it "lets the household owner change the name and IRS payment URL" do
    sign_in_as create(:user, :household_owner)
    get edit_household_path
    expect(response.body).to include("https://www.irs.gov/payments/direct-pay")
    patch household_path, params: { household: { name: "The Roots", irs_payment_url: "https://www.irs.gov/payments" } }
    expect(response).to redirect_to(edit_household_path)
    expect(household.reload).to have_attributes(name: "The Roots", irs_payment_url: "https://www.irs.gov/payments")
  end

  it "rejects a URL that isn't https" do
    sign_in_as create(:user, :household_owner)
    patch household_path, params: { household: { irs_payment_url: "javascript:alert(1)" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(household.reload.irs_payment_url).to eq(Household::DEFAULT_IRS_PAYMENT_URL)
  end

  it "forbids everyone else" do
    sign_in_as user_with_role("owner", business)
    get edit_household_path
    expect(response).to have_http_status(:forbidden)
    patch household_path, params: { household: { name: "Nope" } }
    expect(response).to have_http_status(:forbidden)
  end
end
```

In `spec/requests/navigation_spec.rb`, next to the existing `"Tax parameters"` expectations, add `expect(sidebar).to have_link("Household", href: edit_household_path)` where the household owner's sidebar is checked, and `expect(sidebar).to have_no_link("Household", href: edit_household_path)` where a non-owner's is.

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/requests/households_spec.rb spec/requests/navigation_spec.rb`
Expected: FAIL (`undefined local variable or method 'edit_household_path'`).

- [ ] **Step 3: Route, controller, view, nav**

`config/routes.rb`, under `resources :tax_parameters`: `resource :household, only: %i[edit update]`.

`app/controllers/households_controller.rb`:

```ruby
class HouseholdsController < ApplicationController
  household_page
  before_action :require_household_owner!
  before_action { @household = Household.instance }

  def edit
  end

  def update
    if @household.update(params.expect(household: %i[name irs_payment_url]))
      redirect_to edit_household_path, notice: "Household saved."
    else
      render :edit, status: :unprocessable_content
    end
  end
end
```

`app/views/households/edit.html.erb`:

```erb
<header class="page-header"><h1>Household</h1></header>
<%= form_with model: @household, url: household_path, method: :patch do |f| %>
  <%= render "shared/errors", record: @household %>
  <p><%= f.label :name %> <%= f.text_field :name, required: true %></p>
  <p>
    <%= f.label :irs_payment_url, "IRS payment site" %>
    <%= f.url_field :irs_payment_url, size: 50, required: true %>
    <small class="muted">Opened by "Pay on IRS.gov" on the taxes page and the dashboard.</small>
  </p>
  <%= f.submit "Save" %>
<% end %>
```

`app/helpers/navigation_helper.rb`, first entry of `settings_links`: `(nav_link "Household", edit_household_path if user.household_owner?),`.

- [ ] **Step 4: Run, rubocop, commit**

Run: `bundle exec rspec spec/requests/households_spec.rb spec/requests/navigation_spec.rb` → PASS; `bin/rubocop` clean.

```bash
git add app config spec
git commit -m "Tax engine: household settings page with the IRS payment URL

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Taxes page

**Files:**
- Create: `app/controllers/concerns/tax_year_param.rb`, `app/controllers/tax_years_controller.rb`, `app/helpers/tax_years_helper.rb`, `app/views/tax_years/show.html.erb`, `app/views/tax_years/edit.html.erb`, `app/views/tax_years/_due_card.html.erb`, `app/views/tax_years/_installments.html.erb`, `app/views/tax_years/_breakdown.html.erb`, `app/views/tax_years/_worksheet.html.erb`, `app/views/tax_years/_warnings.html.erb`, `app/views/tax_years/_payments.html.erb`, `spec/requests/tax_years_spec.rb`
- Modify: `config/routes.rb`, `app/views/layouts/_sidebar.html.erb`

**Interfaces:**
- Consumes: `Tax.estimate`, `Tax::Estimate`, `TaxYear`, `EstimatedPayment`, `Household#irs_payment_url`.
- Produces:
  - `TaxYearParam#tax_year_from(value) → Integer` (raises `ActiveRecord::RecordNotFound` unless four digits in 2000–2100).
  - Routes: `tax_years_path` (`/taxes`), `tax_year_path(year)`, `edit_tax_year_path(year)`, and nested `tax_year_estimated_payments_path(year)`, `new_tax_year_estimated_payment_path(year)`, `edit_tax_year_estimated_payment_path(year, payment)`, `tax_year_estimated_payment_path(year, payment)` (param `:tax_year_year`; controller in Task 10).
  - Helpers `irs_payment_link(household)`, `tax_period_label(worksheet)`, `tax_payment_debit_label(payment, visible_book_ids)`.
  - Partial `tax_years/_due_card` (locals `estimate:`, `household:`, `show_page_link:`), reused by the dashboard in Task 13.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/tax_years_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Taxes page" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }
  let!(:owner) { create(:user, :household_owner).tap { create(:membership, user: _1, business:, role: "owner") } }
  let!(:accountant) { user_with_role("viewer", business) }
  let(:personal) { create(:business, :personal, household:).tap { create(:membership, user: owner, business: _1, role: "owner") } }

  before do
    create(:tax_parameters, :federal_2026)
    income = create(:category, :income, business:)
    create(:transaction, account: create(:account, business:), category: income, posted_on: Date.new(2026, 2, 1), amount_cents: 2_500_000)
  end

  around { |example| travel_to(Date.new(2026, 5, 1)) { example.run } }

  it "redirects /taxes to the current year" do
    sign_in_as owner
    get tax_years_path
    expect(response).to redirect_to(tax_year_path(2026))
  end

  it "shows pay at least, the due date, the IRS link, the worksheet, and the estimate note" do
    sign_in_as owner
    get tax_year_path(2026)
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("Pay at least").and include("Jun 15, 2026")
    expect(body).to include("This is an estimate. Verify with your accountant.")
    expect(body).to include("<details")
    link = Nokogiri::HTML(body).at_css("a[href='https://www.irs.gov/payments/direct-pay']")
    expect(link.text).to include("Pay on IRS.gov")
    expect(link["target"]).to eq("_blank")
    expect(link["rel"]).to eq("noopener noreferrer")
  end

  it "uses the household's IRS URL" do
    household.update!(irs_payment_url: "https://www.irs.gov/payments")
    sign_in_as owner
    get tax_year_path(2026)
    expect(response.body).to include('href="https://www.irs.gov/payments"')
  end

  it "selects a quarter from the URL and ignores a bad one" do
    sign_in_as owner
    get tax_year_path(2026, quarter: 1)
    expect(response.body).to include("Worksheet for Q1")
    get tax_year_path(2026, quarter: 9)
    expect(response.body).to include("Worksheet for Q2")
  end

  it "asks for missing prior-year figures" do
    sign_in_as owner
    get tax_year_path(2026)
    expect(response.body).to include("Enter last year&#39;s total tax and AGI to use the safe harbor.")
  end

  it "renders a future year and a past year without parameters" do
    sign_in_as owner
    get tax_year_path(2027)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Federal tax figures for 2027 are incomplete.")
    get tax_year_path(2025)
    expect(response.body).to include("Federal tax figures for 2025 are incomplete.")
  end

  it "renders a year that hasn't started when it has parameters" do
    create(:tax_parameters, :federal_2026, year: 2027)
    sign_in_as owner
    get tax_year_path(2027)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pay at least")
  end

  it "404s a malformed or out-of-range year" do
    sign_in_as owner
    %w[1999 2101 abc 010].each do |year|
      get "/taxes/#{year}"
      expect(response).to have_http_status(:not_found), year
    end
  end

  it "lets a viewer of every business read but not edit" do
    sign_in_as accountant
    get tax_year_path(2026)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(edit_tax_year_path(2026))
    get edit_tax_year_path(2026)
    expect(response).to have_http_status(:forbidden)
    patch tax_year_path(2026), params: { tax_year: { prior_year_total_tax: "1" } }
    expect(response).to have_http_status(:forbidden)
  end

  it "404s a user without household access" do
    other = create(:business, household:)
    sign_in_as user_with_role("owner", other)
    get tax_year_path(2026)
    expect(response).to have_http_status(:not_found)
  end

  it "saves prior-year figures, creating the tax year" do
    sign_in_as owner
    patch tax_year_path(2026), params: { tax_year: { prior_year_total_tax: "24,000", prior_year_agi: "118,000" } }
    expect(response).to redirect_to(tax_year_path(2026))
    expect(TaxYear.find_by!(year: 2026)).to have_attributes(prior_year_total_tax_cents: 2_400_000, prior_year_agi_cents: 11_800_000)
  end

  it "re-renders bad prior-year figures" do
    sign_in_as owner
    patch tax_year_path(2026), params: { tax_year: { prior_year_total_tax: "abc" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "shows a personal-book debit to its members but not to the accountant" do
    debit = create(:transaction, account: create(:account, business: personal, name: "Joint Checking"), posted_on: Date.new(2026, 4, 14),
                                 amount_cents: -450_000, payee: "IRS USATAXPYMT")
    create(:estimated_payment, tax_year: create(:tax_year, household:), quarter: 1, paid_on: debit.posted_on, amount_cents: 450_000, debit:)
    sign_in_as owner
    get tax_year_path(2026)
    expect(response.body).to include("IRS USATAXPYMT").and include("Joint Checking")
    delete session_path
    sign_in_as accountant
    get tax_year_path(2026)
    expect(response.body).to include("$4,500.00").and include("Linked to a bank transaction")
    expect(response.body).not_to include("IRS USATAXPYMT")
  end
end
```

If `delete session_path` doesn't sign out in request specs, split the last example into two `it` blocks.

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/requests/tax_years_spec.rb`
Expected: FAIL (no route).

- [ ] **Step 3: Routes, concern, controller**

`config/routes.rb`, under the `resource :household` line from Task 8:

```ruby
  resources :tax_years, path: "taxes", param: :year, only: %i[index show edit update] do
    resources :estimated_payments, path: "payments", only: %i[new create edit update destroy]
  end
```

(The nested controller arrives in Task 10. Until then `raise_on_missing_callback_actions` doesn't matter because the controller doesn't exist; the routes alone are harmless.)

`app/controllers/concerns/tax_year_param.rb`:

```ruby
# A tax year from the URL: four digits in 2000–2100, else 404. Never Integer(): "010" is octal.
module TaxYearParam
  private

  def tax_year_from(value)
    text = value.to_s
    raise ActiveRecord::RecordNotFound unless text.match?(/\A\d{4}\z/) && (2000..2100).cover?(text.to_i)

    text.to_i
  end
end
```

`app/controllers/tax_years_controller.rb`:

```ruby
class TaxYearsController < ApplicationController
  include TaxYearParam

  household_page
  before_action :require_household_access!
  before_action :require_household_owner!, only: %i[edit update]
  before_action -> { @year = tax_year_from(params[:year]) }, except: :index

  def index
    redirect_to tax_year_path(Date.current.year)
  end

  def show
    @household = Household.instance
    @parameters = TaxParameters.for_year(@year)
    quarter = params[:quarter].to_i
    @estimate = Tax.estimate(household: @household, year: @year, quarter: (1..4).cover?(quarter) ? quarter : nil)
    @payments = @household.tax_years.find_by(year: @year)&.estimated_payments&.includes(debit: :account)&.order(:paid_on, :id).to_a
    @visible_book_ids = Current.user.accessible_businesses.ids
    @uncategorized_count = Transaction.for_businesses(Business.business_kind.select(:id)).inbox.where(posted_on: Date.new(@year).all_year).count
  end

  def edit
    @tax_year = Household.instance.tax_years.find_or_initialize_by(year: @year)
  end

  def update
    @tax_year = Household.instance.tax_years.find_or_initialize_by(year: @year)
    if @tax_year.update(params.expect(tax_year: %i[prior_year_total_tax prior_year_agi]))
      redirect_to tax_year_path(@year), notice: "Prior-year figures saved."
    else
      render :edit, status: :unprocessable_content
    end
  end
end
```

- [ ] **Step 4: Helper**

`app/helpers/tax_years_helper.rb`:

```ruby
module TaxYearsHelper
  PERIOD_FACTORS = { 1 => "×4", 2 => "×2.4", 3 => "×1.5", 4 => "×1" }.freeze

  # The URL is validated to be https:// on Household.
  def irs_payment_link(household)
    link_to "Pay on IRS.gov ↗", household.irs_payment_url, class: "button primary", target: "_blank", rel: "noopener noreferrer"
  end

  def tax_period_label(worksheet)
    if worksheet.elapsed_days.nil? then "annualized #{PERIOD_FACTORS.fetch(worksheet.quarter)}"
    elsif worksheet.elapsed_days.zero? then "no activity yet"
    else "projected from #{pluralize(worksheet.elapsed_days, 'day')}"
    end
  end

  def tax_payment_debit_label(payment, visible_book_ids)
    debit = payment.debit
    if debit.nil? then "Entered by hand"
    elsif visible_book_ids.include?(debit.account.business_id) then "#{debit.payee} · #{debit.account.name}"
    else "Linked to a bank transaction"
    end
  end

  def tax_rate_label(bps) = "#{PercentAttribute.format_bps(bps)}%"
end
```

`bin/brakeman` may report "Unsafe model attribute in link_to href" for `irs_payment_link`. If it does, add the warning to `config/brakeman.ignore` (`bin/brakeman -I`) with the note "Household#irs_payment_url is validated to an https:// address", and commit the ignore file in this task.

- [ ] **Step 5: Views**

`app/views/tax_years/show.html.erb`:

```erb
<header class="page-header">
  <h1>Taxes <%= @year %></h1>
  <%= secondary_action "Prior-year figures", edit_tax_year_path(@year) if Current.user.household_owner? %>
</header>
<p class="no-print">
  <%= link_to "← #{@year - 1}", tax_year_path(@year - 1) %>
  <%= link_to "#{@year + 1} →", tax_year_path(@year + 1) %>
</p>
<p class="muted">This is an estimate. Verify with your accountant.</p>

<% if @estimate.nil? %>
  <p class="flash-alert">
    Federal tax figures for <%= @year %> are incomplete.
    <% if Current.user.household_owner? %>
      <%= link_to "Enter them", @parameters ? edit_tax_parameter_path(@parameters) : new_tax_parameter_path(year: @year) %>
    <% end %>
  </p>
<% else %>
  <%= render "tax_years/due_card", estimate: @estimate, household: @household, show_page_link: false %>
  <%= render "tax_years/warnings", estimate: @estimate %>
  <%= render "shared/uncategorized_notice", count: @uncategorized_count, inbox_path: household_inbox_path %>
  <%= render "tax_years/installments", estimate: @estimate %>
  <%= render "tax_years/breakdown", worksheet: @estimate.worksheet %>
  <%= render "tax_years/worksheet", estimate: @estimate, worksheet: @estimate.worksheet %>
<% end %>

<%= render "tax_years/payments", payments: @payments, year: @year, visible_book_ids: @visible_book_ids %>
```

`app/views/tax_years/_due_card.html.erb`:

```erb
<%# Locals: estimate, household, show_page_link. Used on the taxes page and the dashboard. %>
<section class="card tax-due">
  <h2 class="card-title">Estimated tax <small>Q<%= estimate.quarter %> <%= estimate.year %></small></h2>
  <p>
    Pay at least <strong><%= money(estimate.pay_at_least_cents) %></strong>
    by <strong><%= estimate.next_due_on.strftime("%b %-d, %Y") %></strong>
    <small class="muted"><%= due_phrase(estimate.next_due_on) %></small>
  </p>
  <div class="button-group">
    <%= irs_payment_link(household) %>
    <%= link_to "Taxes #{estimate.year}", tax_year_path(estimate.year) if show_page_link %>
  </div>
</section>
```

`app/views/tax_years/_warnings.html.erb`:

```erb
<% estimate.warnings.each do |warning| %>
  <p class="flash-alert">
    <%= warning.message %>
    <%= link_to "Enter them", edit_tax_year_path(estimate.year) if warning.kind == :prior_year_missing && Current.user.household_owner? %>
  </p>
<% end %>
```

`app/views/tax_years/_installments.html.erb`:

```erb
<table class="tax-installments">
  <thead>
    <tr><th>Quarter</th><th>Due</th><th class="num">Regular</th><th class="num">Annualized</th><th class="num">Paid</th><th class="num">Pay at least</th></tr>
  </thead>
  <tbody>
    <% estimate.installments.each do |row| %>
      <tr<%= ' aria-current="true"'.html_safe if row.quarter == estimate.quarter %>>
        <td><%= link_to "Q#{row.quarter}", tax_year_path(estimate.year, quarter: row.quarter) %></td>
        <td><%= row.due_on.strftime("%b %-d, %Y") %></td>
        <td class="num"><%= money(row.regular_cents) %></td>
        <td class="num"><%= row.annualized_cents ? money(row.annualized_cents) : "—" %></td>
        <td class="num"><%= money(row.paid_cents) %></td>
        <td class="num"><strong><%= money(row.pay_at_least_cents) %></strong></td>
      </tr>
    <% end %>
  </tbody>
</table>
<p class="muted">
  Required for the year: <%= money(estimate.required_annual_cents) %>, the lesser of 90% of projected tax (<%= money(estimate.ninety_percent_cents) %>)
  <% if estimate.safe_harbor_cents %>and the prior-year safe harbor (<%= money(estimate.safe_harbor_cents) %>)<% end %>.
  "Pay at least" is the lesser of the regular and annualized installments, an approximation of the Form 2210 rules.
</p>
```

`app/views/tax_years/_breakdown.html.erb`:

```erb
<h2>Businesses</h2>
<table>
  <thead>
    <tr><th>Business</th><th class="num">Profit so far</th><th class="num">Annualized</th><th class="num">Home office used</th><th class="num">Carryover</th><th></th></tr>
  </thead>
  <tbody>
    <% worksheet.business_lines.each do |line| %>
      <tr>
        <td><%= line.business.name %></td>
        <td class="num"><%= money(line.ytd_cents) %></td>
        <td class="num"><%= money(line.annualized_cents) %></td>
        <td class="num"><%= money(line.home_office_used_cents) %></td>
        <td class="num"><%= money(line.carryover_cents) %></td>
        <td></td>
      </tr>
    <% end %>
  </tbody>
</table>

<h2>Self-employment tax</h2>
<table>
  <thead>
    <tr><th>Person</th><th class="num">Net profit</th><th class="num">SE earnings</th><th class="num">SE tax</th><th class="num">Health insurance</th><th class="num">Retirement</th><th></th></tr>
  </thead>
  <tbody>
    <% worksheet.person_lines.each do |line| %>
      <tr>
        <td><%= line.person.name %></td>
        <td class="num"><%= money(line.net_profit_cents) %></td>
        <td class="num"><%= money(line.se_earnings_cents) %></td>
        <td class="num"><%= money(line.se_tax_cents) %></td>
        <td class="num"><%= money(line.health_insurance_cents) %></td>
        <td class="num"><%= money(line.retirement_cents) %></td>
        <td></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

The empty last cells get edit links in Tasks 11 and 12.

`app/views/tax_years/_worksheet.html.erb`:

```erb
<details class="tax-worksheet">
  <summary>Worksheet for Q<%= worksheet.quarter %> (<%= tax_period_label(worksheet) %>)</summary>
  <p class="muted">Business profit is annualized; home office, health insurance, and retirement are full-year amounts applied after annualizing.</p>
  <table>
    <tbody>
      <% worksheet.business_lines.each do |line| %>
        <tr><th colspan="2"><%= line.business.name %></th></tr>
        <tr><td>Profit through the period</td><td class="num"><%= money(line.ytd_cents) %></td></tr>
        <tr><td>Annualized</td><td class="num"><%= money(line.annualized_cents) %></td></tr>
        <tr><td>Home office (full year <%= money(line.home_office_cents) %>) used</td><td class="num"><%= money(line.home_office_used_cents) %></td></tr>
        <tr><td>Net profit</td><td class="num"><%= money(line.net_profit_cents) %></td></tr>
      <% end %>
      <% worksheet.person_lines.each do |line| %>
        <tr><th colspan="2"><%= line.person.name %></th></tr>
        <tr><td>Net profit from their businesses</td><td class="num"><%= money(line.net_profit_cents) %></td></tr>
        <tr><td>SE earnings</td><td class="num"><%= money(line.se_earnings_cents) %></td></tr>
        <tr><td>Social Security</td><td class="num"><%= money(line.ss_cents) %></td></tr>
        <tr><td>Medicare</td><td class="num"><%= money(line.medicare_cents) %></td></tr>
        <tr><td>Half of SE tax (deductible)</td><td class="num"><%= money(line.half_se_cents) %></td></tr>
        <tr><td>Self-employed health insurance (capped)</td><td class="num"><%= money(line.health_insurance_cents) %></td></tr>
        <tr><td>Retirement contribution</td><td class="num"><%= money(line.retirement_cents) %></td></tr>
      <% end %>
      <tr><th colspan="2">Household</th></tr>
      <tr><td>Total net profit</td><td class="num"><%= money(worksheet.total_net_profit_cents) %></td></tr>
      <tr><td>Adjusted gross income</td><td class="num"><%= money(worksheet.agi_cents) %></td></tr>
      <tr><td>Standard deduction</td><td class="num"><%= money(worksheet.standard_deduction_cents) %></td></tr>
      <tr><td>Taxable income before QBI</td><td class="num"><%= money(worksheet.taxable_before_qbi_cents) %></td></tr>
      <tr><td>Qualified business income</td><td class="num"><%= money(worksheet.qbi_cents) %></td></tr>
      <tr><td>QBI deduction</td><td class="num"><%= money(worksheet.qbi_deduction_cents) %></td></tr>
      <tr><td>Taxable income</td><td class="num"><%= money(worksheet.taxable_income_cents) %></td></tr>
      <% worksheet.bracket_slices.each do |slice| %>
        <tr><td><%= tax_rate_label(slice.rate_bps) %> of <%= money(slice.taxed_cents) %></td><td class="num"><%= money(slice.tax_cents) %></td></tr>
      <% end %>
      <tr><td>Income tax</td><td class="num"><%= money(worksheet.income_tax_cents) %></td></tr>
      <tr><td>Self-employment tax</td><td class="num"><%= money(worksheet.se_tax_cents) %></td></tr>
      <tr><td>Additional Medicare tax</td><td class="num"><%= money(worksheet.additional_medicare_cents) %></td></tr>
      <tr><th>Total projected tax</th><th class="num"><%= money(worksheet.total_tax_cents) %></th></tr>
      <tr><td>90% of projected tax</td><td class="num"><%= money(estimate.ninety_percent_cents) %></td></tr>
      <tr><td>Prior-year safe harbor</td><td class="num"><%= estimate.safe_harbor_cents ? money(estimate.safe_harbor_cents) : "—" %></td></tr>
      <tr><th>Required for the year</th><th class="num"><%= money(estimate.required_annual_cents) %></th></tr>
    </tbody>
  </table>
</details>
```

`app/views/tax_years/_payments.html.erb`:

```erb
<section class="tax-payments">
  <h2>Payments</h2>
  <% if payments.empty? %>
    <p class="muted">No estimated payments recorded for <%= year %>.</p>
  <% else %>
    <table>
      <thead><tr><th>Paid</th><th>Quarter</th><th class="num">Amount</th><th>Bank transaction</th><th></th></tr></thead>
      <tbody>
        <% payments.each do |payment| %>
          <tr id="<%= dom_id(payment) %>">
            <td><%= payment.paid_on.iso8601 %></td>
            <td>Q<%= payment.quarter %></td>
            <td class="num"><%= money(payment.amount_cents) %></td>
            <td><%= tax_payment_debit_label(payment, visible_book_ids) %></td>
            <td></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>
</section>
```

`app/views/tax_years/edit.html.erb`:

```erb
<header class="page-header"><h1>Prior-year figures for <%= @year %></h1></header>
<p class="muted">From your <%= @year - 1 %> federal return: total tax and adjusted gross income. They set the safe harbor.</p>
<%= form_with model: @tax_year, url: tax_year_path(@year), method: :patch do |f| %>
  <%= render "shared/errors", record: @tax_year %>
  <p><%= f.label :prior_year_total_tax, "#{@year - 1} total tax ($)" %> <%= f.text_field :prior_year_total_tax %></p>
  <p><%= f.label :prior_year_agi, "#{@year - 1} adjusted gross income ($)" %> <%= f.text_field :prior_year_agi %></p>
  <%= f.submit "Save" %>
<% end %>
```

`app/views/layouts/_sidebar.html.erb`, in the household group after "Household aging": `<%= nav_link "Taxes", tax_years_path if Current.user.can_view_household? %>`.

- [ ] **Step 6: Run, rubocop, brakeman, commit**

Run: `bundle exec rspec spec/requests/tax_years_spec.rb spec/requests/navigation_spec.rb` → PASS; `bin/rubocop`; `bin/brakeman --no-pager` (see Step 4).

```bash
git add app config spec
git commit -m "Tax engine: taxes page with due card, installments, worksheet, payment log

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Recording estimated payments

**Files:**
- Create: `app/models/tax/payment_candidates.rb`, `app/controllers/estimated_payments_controller.rb`, `app/views/estimated_payments/new.html.erb`, `app/views/estimated_payments/edit.html.erb`, `app/views/estimated_payments/_form.html.erb`, `spec/models/tax/payment_candidates_spec.rb`, `spec/requests/estimated_payments_spec.rb`, `spec/system/estimated_payments_spec.rb`
- Modify: `app/views/tax_years/_payments.html.erb`

**Interfaces:**
- Consumes: `EstimatedPayment#link`, `TaxYear.for`, `TaxYearParam`, the nested routes from Task 9.
- Produces: `Tax::PaymentCandidates.scope_for(user) → Transaction relation`, `Tax::PaymentCandidates.for(user:, year:, query: nil) → relation` (money out, dated Jan 1 of `year` through Jan 31 of `year + 1`, not yet recorded, IRS-looking payees first, then newest, at most 50).

- [ ] **Step 1: Write the failing specs**

`spec/models/tax/payment_candidates_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tax::PaymentCandidates do
  let(:business) { create(:business) }
  let(:user) { user_with_role("owner", business) }
  let(:account) { create(:account, business:) }

  def debit(payee, on, cents = -10_000, to: account) = create(:transaction, account: to, payee:, posted_on: on, amount_cents: cents)

  it "lists money out in the window, IRS payees first, then newest" do
    groceries = debit("KROGER", Date.new(2026, 6, 20))
    irs = debit("IRS USATAXPYMT", Date.new(2026, 4, 14))
    eftps = debit("eftps payment", Date.new(2026, 1, 2))
    january = debit("RENT", Date.new(2027, 1, 31))
    debit("TOO EARLY", Date.new(2025, 12, 31))
    debit("TOO LATE", Date.new(2027, 2, 1))
    debit("DEPOSIT", Date.new(2026, 5, 1), 10_000)
    expect(described_class.for(user:, year: 2026).to_a).to eq([ irs, eftps, january, groceries ])
  end

  it "filters by payee" do
    irs = debit("IRS USATAXPYMT", Date.new(2026, 4, 14))
    debit("KROGER", Date.new(2026, 6, 20))
    expect(described_class.for(user:, year: 2026, query: "usatax").to_a).to eq([ irs ])
  end

  it "treats % and _ in the search as text" do
    debit("KROGER", Date.new(2026, 6, 20))
    expect(described_class.for(user:, year: 2026, query: "%").to_a).to eq([])
  end

  it "drops debits already recorded" do
    recorded = debit("IRS USATAXPYMT", Date.new(2026, 4, 14))
    create(:estimated_payment, debit: recorded, amount_cents: 10_000)
    expect(described_class.for(user:, year: 2026).to_a).to eq([])
  end

  it "only sees the user's books" do
    debit("IRS USATAXPYMT", Date.new(2026, 4, 14), to: create(:account, business: create(:business)))
    expect(described_class.for(user:, year: 2026).to_a).to eq([])
  end
end
```

`spec/requests/estimated_payments_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Estimated payments" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }
  let!(:personal) { create(:business, :personal, household:) }
  let!(:owner) do
    create(:user, :household_owner).tap do |user|
      create(:membership, user:, business:, role: "owner")
      create(:membership, user:, business: personal, role: "owner")
    end
  end
  let(:joint) { create(:account, business: personal, name: "Joint Checking") }
  let!(:irs) { create(:transaction, account: joint, payee: "IRS USATAXPYMT", posted_on: Date.new(2026, 6, 12), amount_cents: -450_000) }

  it "lists candidates and records a payment from the picked debit" do
    sign_in_as owner
    get new_tax_year_estimated_payment_path(2026, q: "IRS")
    expect(response.body).to include("IRS USATAXPYMT")
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { debit_id: irs.id } }
    expect(response).to redirect_to(tax_year_path(2026))
    expect(EstimatedPayment.last).to have_attributes(debit: irs, amount_cents: 450_000, paid_on: Date.new(2026, 6, 12), quarter: 2)
  end

  it "records a payment by hand with the quarter from its date" do
    sign_in_as owner
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { paid_on: "2026-04-15", amount: "1,200", quarter: "" } }
    expect(EstimatedPayment.last).to have_attributes(debit: nil, amount_cents: 120_000, quarter: 1)
  end

  it "refuses money in" do
    deposit = create(:transaction, account: joint, amount_cents: 5_000, posted_on: Date.new(2026, 6, 1))
    sign_in_as owner
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { debit_id: deposit.id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be money paid out")
    expect(EstimatedPayment.count).to eq(0)
  end

  it "refuses a debit already recorded" do
    sign_in_as owner
    2.times { post tax_year_estimated_payments_path(2026), params: { estimated_payment: { debit_id: irs.id } } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("is already recorded as a payment")
    expect(EstimatedPayment.count).to eq(1)
  end

  it "404s a debit in a book the user can't see" do
    hidden = create(:transaction, account: create(:account, business: create(:business, household:)), amount_cents: -100)
    sign_in_as owner
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { debit_id: hidden.id } }
    expect(response).to have_http_status(:not_found)
  end

  it "edits and deletes a payment" do
    payment = create(:estimated_payment, tax_year: create(:tax_year, household:), amount_cents: 100_000)
    sign_in_as owner
    patch tax_year_estimated_payment_path(2026, payment), params: { estimated_payment: { amount: "1,500", quarter: "3" } }
    expect(payment.reload).to have_attributes(amount_cents: 150_000, quarter: 3)
    delete tax_year_estimated_payment_path(2026, payment)
    expect(EstimatedPayment.count).to eq(0)
  end

  it "404s a payment from another year's URL" do
    payment = create(:estimated_payment, tax_year: create(:tax_year, household:, year: 2025))
    sign_in_as owner
    get edit_tax_year_estimated_payment_path(2026, payment)
    expect(response).to have_http_status(:not_found)
  end

  it "forbids a viewer of every business" do
    sign_in_as user_with_role("viewer", business)
    get new_tax_year_estimated_payment_path(2026)
    expect(response).to have_http_status(:forbidden)
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { paid_on: "2026-04-15", amount: "1" } }
    expect(response).to have_http_status(:forbidden)
  end
end
```

`spec/system/estimated_payments_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Recording an estimated payment" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, household:, name: "Pat Consulting"), owner:) }
  let!(:personal) { PersonalBookProvisioner.call(household) }

  it "picks the IRS debit and sees the amount due drop" do
    travel_to Date.new(2026, 5, 1) do
      create(:tax_parameters, :federal_2026)
      income = business.categories.find_by!(schedule_c_line: "1")
      create(:transaction, account: business.accounts.first, category: income, posted_on: Date.new(2026, 2, 1), amount_cents: 2_500_000)
      create(:transaction, account: create(:account, business: personal, name: "Joint Checking"), payee: "IRS USATAXPYMT",
                           posted_on: Date.new(2026, 4, 14), amount_cents: -100_000)

      system_sign_in_as owner
      visit tax_year_path(2026)
      before = find(".tax-due strong", match: :first).text
      click_on "Record a payment"
      fill_in "Payee contains", with: "IRS"
      click_on "Search"
      click_on "Use this"
      expect(page).to have_content("Payment recorded.")
      expect(page).to have_content("IRS USATAXPYMT · Joint Checking")
      expect(find(".tax-due strong", match: :first).text).not_to eq(before)
    end
  end
end
```

`PersonalBookProvisioner.call(household)` gives the household owner an owner membership (tithing spec §3.1), and `BusinessProvisioner` creates a "Cash" account and the "Sales" category on line 1, so the lookups above find them.

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/tax/payment_candidates_spec.rb spec/requests/estimated_payments_spec.rb spec/system/estimated_payments_spec.rb`
Expected: FAIL.

- [ ] **Step 3: `Tax::PaymentCandidates`**

`app/models/tax/payment_candidates.rb`:

```ruby
module Tax
  # Bank transactions a household owner can record as an estimated payment.
  module PaymentCandidates
    LIMIT = 50
    IRS_FIRST_SQL = "CASE WHEN transactions.payee LIKE '%IRS%' OR transactions.payee LIKE '%USATAXPYMT%' " \
                    "OR transactions.payee LIKE '%EFTPS%' THEN 0 ELSE 1 END".freeze

    module_function

    def scope_for(user) = Transaction.for_businesses(user.accessible_businesses.select(:id))

    def for(user:, year:, query: nil)
      scope = scope_for(user).where("transactions.amount_cents < 0").where(posted_on: Date.new(year, 1, 1)..Date.new(year + 1, 1, 31))
        .where.missing(:estimated_payment)
      scope = scope.where("transactions.payee LIKE ? ESCAPE '\\'", "%#{Transaction.sanitize_sql_like(query.strip)}%") if query.present?
      scope.includes(account: :business).order(Arel.sql(IRS_FIRST_SQL)).order(posted_on: :desc, id: :desc).limit(LIMIT)
    end
  end
end
```

SQLite's `LIKE` is case-insensitive for ASCII, so "eftps payment" sorts first and "usatax" matches.

- [ ] **Step 4: Controller**

`app/controllers/estimated_payments_controller.rb`:

```ruby
class EstimatedPaymentsController < ApplicationController
  include TaxYearParam

  household_page
  before_action :require_household_access!
  before_action :require_household_owner!
  before_action -> { @year = tax_year_from(params[:tax_year_year]) }
  before_action :set_payment, only: %i[edit update destroy]

  def new
    @payment = EstimatedPayment.new
    load_candidates
  end

  def create
    @payment = TaxYear.for(Household.instance, @year).estimated_payments.new
    debit_id = params.dig(:estimated_payment, :debit_id)
    if debit_id.present?
      @payment.link(Tax::PaymentCandidates.scope_for(Current.user).find(debit_id))
    else
      @payment.assign_attributes(payment_params)
    end

    if @payment.save
      redirect_to tax_year_path(@year), notice: "Payment recorded."
    else
      load_candidates
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @payment.update(payment_params)
      redirect_to tax_year_path(@year), notice: "Payment updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @payment.destroy!
    redirect_to tax_year_path(@year), notice: "Payment deleted."
  end

  private

  def set_payment
    @payment = EstimatedPayment.joins(:tax_year).where(tax_years: { household_id: Household.instance.id, year: @year }).find(params[:id])
  end

  def payment_params = params.expect(estimated_payment: %i[paid_on amount quarter])

  def load_candidates
    @query = params[:q].to_s
    @candidates = Tax::PaymentCandidates.for(user: Current.user, year: @year, query: @query)
  end
end
```

- [ ] **Step 5: Views**

`app/views/estimated_payments/_form.html.erb`:

```erb
<%= form_with model: payment, url: url, method: method do |f| %>
  <p><%= f.label :paid_on, "Date paid" %> <%= f.date_field :paid_on, required: true %></p>
  <p><%= f.label :amount, "Amount ($)" %> <%= f.text_field :amount, required: true %></p>
  <p><%= f.label :quarter %> <%= f.select :quarter, (1..4).map { [ "Q#{_1}", _1 ] }, include_blank: "From the date" %></p>
  <%= f.submit submit %>
<% end %>
```

`app/views/estimated_payments/new.html.erb`:

```erb
<header class="page-header"><h1>Record an estimated payment for <%= @year %></h1></header>
<%= render "shared/errors", record: @payment %>

<h2>Pick the bank transaction</h2>
<%= form_with url: new_tax_year_estimated_payment_path(@year), method: :get, class: "filters" do |f| %>
  <%= f.label :q, "Payee contains" %>
  <%= f.search_field :q, value: @query %>
  <%= f.submit "Search", name: nil %>
<% end %>
<% if @candidates.empty? %>
  <p class="muted">No money-out transactions match between Jan 1, <%= @year %> and Jan 31, <%= @year + 1 %>.</p>
<% else %>
  <table>
    <thead><tr><th>Date</th><th>Payee</th><th>Account</th><th class="num">Amount</th><th></th></tr></thead>
    <tbody>
      <% @candidates.each do |debit| %>
        <tr>
          <td><%= debit.posted_on.iso8601 %></td>
          <td><%= debit.payee %></td>
          <td><%= book_label(debit.account.business) %> · <%= debit.account.name %></td>
          <td class="num"><%= money(-debit.amount_cents) %></td>
          <td><%= button_to "Use this", tax_year_estimated_payments_path(@year), params: { estimated_payment: { debit_id: debit.id } }, class: "button" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>

<h2>Or enter it by hand</h2>
<p class="muted">For a payment with no bank transaction, such as last year's overpayment applied to this year.</p>
<%= render "form", payment: @payment, url: tax_year_estimated_payments_path(@year), method: :post, submit: "Record payment" %>
```

`app/views/estimated_payments/edit.html.erb`:

```erb
<header class="page-header"><h1>Edit payment</h1></header>
<%= render "shared/errors", record: @payment %>
<% if @payment.debit %>
  <p class="muted">Linked to <%= tax_payment_debit_label(@payment, Current.user.accessible_businesses.ids) %>.</p>
<% end %>
<%= render "form", payment: @payment, url: tax_year_estimated_payment_path(@year, @payment), method: :patch, submit: "Save" %>
```

In `app/views/tax_years/_payments.html.erb`: after the `<h2>`, add
`<%= secondary_action "Record a payment", new_tax_year_estimated_payment_path(year) if Current.user.household_owner? %>`,
and fill the empty last cell of each row:

```erb
            <td>
              <% if Current.user.household_owner? %>
                <div class="button-group">
                  <%= link_to "Edit", edit_tax_year_estimated_payment_path(year, payment) %>
                  <%= confirm_button "Delete", tax_year_estimated_payment_path(year, payment), method: :delete, confirm: "Delete this payment?" %>
                </div>
              <% end %>
            </td>
```

`confirm_button` wraps `button_to`, which posts unless given `method: :delete`.

- [ ] **Step 6: Run, rubocop, commit**

Run: `bundle exec rspec spec/models/tax spec/requests/estimated_payments_spec.rb spec/requests/tax_years_spec.rb spec/system/estimated_payments_spec.rb` → PASS; `bin/rubocop` clean.

```bash
git add app spec
git commit -m "Tax engine: record estimated payments by picking the IRS debit or by hand

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 11: Home office form and Schedule C line 30

**Files:**
- Create: `app/controllers/home_offices_controller.rb`, `app/views/home_offices/edit.html.erb`, `spec/requests/home_offices_spec.rb`
- Modify: `config/routes.rb`, `app/controllers/schedule_cs_controller.rb`, `app/views/schedule_cs/show.html.erb`, `app/helpers/tax_years_helper.rb`, `app/views/tax_years/_breakdown.html.erb`

**Interfaces:**
- Consumes: `HomeOffice` (Task 6), `ScheduleCSummary` home office split (Task 7), `TaxYearParam` (Task 9).
- Produces: `edit_business_home_office_path(business, year)`, `business_home_office_path(business, year)` (PATCH); helper `can_edit_home_office?(business_id) → Boolean`.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/home_offices_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Home office" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }
  let!(:household_owner) { create(:user, :household_owner).tap { create(:membership, user: _1, business:, role: "owner") } }
  let(:simplified) { { home_office: { calculation: "simplified", office_sqft: "200" } } }

  before do
    create(:tax_parameters, :federal_2026)
    income = create(:category, :income, business:)
    create(:transaction, account: create(:account, business:), category: income, posted_on: Date.new(2026, 2, 1), amount_cents: 50_000)
  end

  it "lets the household owner add one, capped on Schedule C line 30" do
    sign_in_as household_owner
    get edit_business_home_office_path(business, 2026)
    expect(response).to have_http_status(:ok)
    patch business_home_office_path(business, 2026), params: simplified
    expect(response).to redirect_to(business_schedule_c_path(business, year: 2026))
    follow_redirect!
    # 200 sq ft × $5 = $1,000.00, capped at the $500.00 tentative profit
    line30 = Nokogiri::HTML(response.body).css("tr").find { _1.text.include?("Line 30") }
    expect(line30.text).to include("$500.00").and include("Edit home office")
    expect(response.body).to include("Tentative profit")
  end

  it "lets a business owner who isn't the household owner edit their own" do
    sign_in_as user_with_role("owner", business)
    patch business_home_office_path(business, 2026), params: simplified
    expect(HomeOffice.find_by!(business:, year: 2026).office_sqft).to eq(200)
  end

  it "forbids an editor" do
    sign_in_as user_with_role("editor", business)
    get edit_business_home_office_path(business, 2026)
    expect(response).to have_http_status(:forbidden)
    patch business_home_office_path(business, 2026), params: simplified
    expect(response).to have_http_status(:forbidden)
  end

  it "404s a non-member, the personal book, and a bad year" do
    sign_in_as user_with_role("owner", create(:business, household:))
    get edit_business_home_office_path(business, 2026)
    expect(response).to have_http_status(:not_found)

    personal = create(:business, :personal, household:)
    create(:membership, user: household_owner, business: personal, role: "owner")
    delete session_path
    sign_in_as household_owner
    get edit_business_home_office_path(personal, 2026)
    expect(response).to have_http_status(:not_found)
    get "/businesses/#{business.id}/home_offices/abc/edit"
    expect(response).to have_http_status(:not_found)
  end

  it "re-renders a regular office bigger than the home" do
    sign_in_as household_owner
    patch business_home_office_path(business, 2026), params: { home_office: { calculation: "regular", office_sqft: "300", home_sqft: "200" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be at least the office&#39;s square feet")
  end

  it "shows a dash and an add link on Schedule C when there's none, and no link for a viewer" do
    sign_in_as household_owner
    get business_schedule_c_path(business, year: 2026)
    expect(response.body).to include("Add home office")
    delete session_path
    sign_in_as user_with_role("viewer", business)
    get business_schedule_c_path(business, year: 2026)
    expect(response.body).not_to include("Add home office")
  end

  it "links the home office from the taxes page for those who can edit it" do
    travel_to Date.new(2026, 5, 1) do
      sign_in_as household_owner
      get tax_year_path(2026)
      expect(response.body).to include(edit_business_home_office_path(business, 2026))
    end
  end
end
```

If `delete session_path` doesn't sign out between users, split those examples.

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/requests/home_offices_spec.rb`
Expected: FAIL (no route).

- [ ] **Step 3: Route, controller, view**

`config/routes.rb`, inside `resources :businesses`, after `resources :mileage_entries`: `resources :home_offices, only: %i[edit update], param: :year`.

`app/controllers/home_offices_controller.rb`:

```ruby
class HomeOfficesController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly
  include TaxYearParam

  before_action :require_home_office_editor!
  before_action { @home_office = @business.home_offices.find_or_initialize_by(year: tax_year_from(params[:year])) }

  def edit
  end

  def update
    if @home_office.update(params.expect(home_office: [ :calculation, :office_sqft, :home_sqft, *HomeOffice::COSTS ]))
      redirect_to business_schedule_c_path(@business, year: @home_office.year), notice: "Home office saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def require_home_office_editor!
    head :forbidden unless Current.user.household_owner? || @membership.owner?
  end
end
```

`app/views/home_offices/edit.html.erb`:

```erb
<header class="page-header"><h1>Home office <%= @home_office.year %> — <%= @business.name %></h1></header>
<%= form_with model: @home_office, url: business_home_office_path(@business, @home_office.year), method: :patch do |f| %>
  <%= render "shared/errors", record: @home_office %>
  <fieldset>
    <legend>Method</legend>
    <p><%= f.radio_button :calculation, "simplified" %> <%= f.label :calculation_simplified, "Simplified ($ per square foot, up to the yearly maximum)" %></p>
    <p><%= f.radio_button :calculation, "regular" %> <%= f.label :calculation_regular, "Regular (the office's share of home costs)" %></p>
  </fieldset>
  <p><%= f.label :office_sqft, "Office (sq ft)" %> <%= f.number_field :office_sqft, min: 1, required: true %></p>
  <fieldset>
    <legend>Regular method only</legend>
    <p><%= f.label :home_sqft, "Whole home (sq ft)" %> <%= f.number_field :home_sqft, min: 1 %></p>
    <p class="muted">Yearly totals for the whole home; the office's share is applied for you.</p>
    <p><%= f.label :rent, "Rent ($)" %> <%= f.text_field :rent %></p>
    <p><%= f.label :mortgage_interest, "Mortgage interest ($)" %> <%= f.text_field :mortgage_interest %></p>
    <p><%= f.label :utilities, "Utilities ($)" %> <%= f.text_field :utilities %></p>
    <p><%= f.label :insurance, "Insurance ($)" %> <%= f.text_field :insurance %></p>
    <p><%= f.label :repairs, "Repairs and maintenance ($)" %> <%= f.text_field :repairs %></p>
    <p><%= f.label :other, "Other ($)" %> <%= f.text_field :other %></p>
    <p><%= f.label :depreciation, "Depreciation, business portion ($, from your accountant)" %> <%= f.text_field :depreciation %></p>
  </fieldset>
  <%= f.submit "Save" %>
<% end %>
```

- [ ] **Step 4: Schedule C**

In `app/controllers/schedule_cs_controller.rb#show`, before building `@summary`:

```ruby
    @home_office = @business.home_offices.find_by(year: @year)
    @can_edit_home_office = Current.user.household_owner? || current_membership.owner?
```

and pass `home_office_cents: @home_office&.deduction_cents(TaxParameters.for_year(@year))` to `Reports::ScheduleCSummary.new`.

In `app/views/schedule_cs/show.html.erb`, delete the row `<tr><td><%= ScheduleC.label("30") %></td><td class="num">—</td></tr>` and replace the three closing rows with:

```erb
    <tr><th>Gross income</th><th class="num"><%= money(@summary.gross_income_cents) %></th></tr>
    <tr><th>Total expenses</th><th class="num"><%= money(@summary.total_expenses_cents) %></th></tr>
    <tr><th>Tentative profit (line 29)</th><th class="num"><%= money(@summary.tentative_profit_cents) %></th></tr>
    <tr>
      <td><%= ScheduleC.label("30") %></td>
      <td class="num"><%= @summary.home_office_used_cents ? money(@summary.home_office_used_cents) : "—" %></td>
      <% if @can_edit_home_office %>
        <td class="no-print"><%= link_to @home_office ? "Edit home office" : "Add home office", edit_business_home_office_path(@business, @year) %></td>
      <% end %>
    </tr>
    <tr><th>Net profit</th><th class="num"><%= money(@summary.net_profit_cents) %></th></tr>
```

- [ ] **Step 5: Link from the taxes page**

Add to `app/helpers/tax_years_helper.rb`:

```ruby
  def can_edit_home_office?(business_id)
    Current.user.household_owner? || Current.user.memberships.owner.exists?(business_id: business_id)
  end
```

In `app/views/tax_years/_breakdown.html.erb`, fill the empty last cell of the business rows:

```erb
        <td><%= link_to "Home office", edit_business_home_office_path(line.business.id, @year) if can_edit_home_office?(line.business.id) %></td>
```

(`@year` is set by `TaxYearsController#show`.)

- [ ] **Step 6: Run, rubocop, commit**

Run: `bundle exec rspec spec/requests/home_offices_spec.rb spec/requests/reports_spec.rb spec/requests/tax_years_spec.rb` → PASS (if a reports spec asserted the old "—" row order, update it to the new rows). `bin/rubocop` clean.

```bash
git add app config spec
git commit -m "Tax engine: home office form and Schedule C line 30

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Per-person adjustments

**Files:**
- Create: `app/controllers/person_adjustments_controller.rb`, `app/views/person_adjustments/edit.html.erb`, `spec/requests/person_adjustments_spec.rb`
- Modify: `config/routes.rb`, `app/views/people/index.html.erb`, `app/helpers/tax_years_helper.rb`, `app/views/tax_years/_breakdown.html.erb`

**Interfaces:**
- Consumes: `PersonAdjustment` (Task 6), `TaxYearParam` (Task 9).
- Produces: `edit_person_adjustment_path(person, year)`, `person_adjustment_path(person, year)` (PATCH); helper `can_edit_adjustments?(person_id) → Boolean`.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/person_adjustments_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Tax adjustments" do
  let!(:household) { create(:household) }
  let!(:owner_person) { create(:person, household:, name: "Alex") }
  let!(:spouse_user) { create(:user) }
  let!(:spouse) { create(:person, household:, name: "Whitney", user: spouse_user) }
  let!(:business) { create(:business, household:, person: owner_person) }
  let!(:spouse_business) { create(:business, household:, person: spouse) }
  let(:params) { { person_adjustment: { se_health_insurance: "7,200", retirement_contribution: "6,000", retirement_plan: "sep" } } }

  before do
    create(:membership, user: spouse_user, business: spouse_business, role: "editor")
    create(:membership, user: spouse_user, business:, role: "viewer")
  end

  it "lets the household owner edit anyone's" do
    sign_in_as create(:user, :household_owner)
    patch person_adjustment_path(spouse, 2026), params: params
    expect(response).to redirect_to(tax_year_path(2026))
    expect(spouse.person_adjustments.find_by!(year: 2026)).to have_attributes(se_health_insurance_cents: 720_000, retirement_plan: "sep")
  end

  it "lets a person's own user edit theirs" do
    sign_in_as spouse_user
    get edit_person_adjustment_path(spouse, 2026)
    expect(response).to have_http_status(:ok)
    patch person_adjustment_path(spouse, 2026), params: params
    expect(response).to redirect_to(tax_year_path(2026))
  end

  it "forbids editing someone else's when the user can see the household" do
    sign_in_as spouse_user
    get edit_person_adjustment_path(owner_person, 2026)
    expect(response).to have_http_status(:forbidden)
  end

  it "404s someone else's when the user can't see the household" do
    sign_in_as user_with_role("owner", create(:business, household:, person: owner_person))
    get edit_person_adjustment_path(spouse, 2026)
    expect(response).to have_http_status(:not_found)
  end

  it "requires a plan with a contribution" do
    sign_in_as spouse_user
    patch person_adjustment_path(spouse, 2026), params: { person_adjustment: { retirement_contribution: "6,000", retirement_plan: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Retirement plan is required with a contribution")
  end

  it "404s a bad year" do
    sign_in_as spouse_user
    get "/people/#{spouse.id}/adjustments/20x6/edit"
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/requests/person_adjustments_spec.rb`
Expected: FAIL (no route).

- [ ] **Step 3: Route, controller, view**

`config/routes.rb`: change `resources :people, only: %i[index new create edit update]` to

```ruby
  resources :people, only: %i[index new create edit update] do
    resources :adjustments, only: %i[edit update], param: :year, controller: "person_adjustments"
  end
```

`app/controllers/person_adjustments_controller.rb`:

```ruby
class PersonAdjustmentsController < ApplicationController
  include TaxYearParam

  household_page
  before_action { @person = Household.instance.people.find(params[:person_id]) }
  before_action :require_adjustment_editor!
  before_action { @adjustment = @person.person_adjustments.find_or_initialize_by(year: tax_year_from(params[:year])) }

  def edit
  end

  def update
    if @adjustment.update(params.expect(person_adjustment: %i[se_health_insurance retirement_contribution retirement_plan]))
      redirect_to tax_year_path(@adjustment.year), notice: "Adjustments saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def require_adjustment_editor!
    return if Current.user.household_owner? || @person.user_id == Current.user.id

    head(Current.user.can_view_household? ? :forbidden : :not_found)
  end
end
```

`app/views/person_adjustments/edit.html.erb`:

```erb
<header class="page-header"><h1>Tax adjustments <%= @adjustment.year %> — <%= @person.name %></h1></header>
<p class="muted">Expected totals for the whole year. They lower adjusted gross income in the estimate.</p>
<%= form_with model: @adjustment, url: person_adjustment_path(@person, @adjustment.year), method: :patch do |f| %>
  <%= render "shared/errors", record: @adjustment %>
  <p><%= f.label :se_health_insurance, "Self-employed health insurance premiums ($)" %> <%= f.text_field :se_health_insurance %></p>
  <p><%= f.label :retirement_contribution, "Retirement contribution ($)" %> <%= f.text_field :retirement_contribution %></p>
  <p><%= f.label :retirement_plan, "Plan" %> <%= f.select :retirement_plan, PersonAdjustment::PLANS.invert, include_blank: "None" %></p>
  <%= f.submit "Save" %>
<% end %>
```

- [ ] **Step 4: Links**

In `app/views/people/index.html.erb`, add to each row's button group: `<%= link_to "Tax adjustments", edit_person_adjustment_path(person, Date.current.year) %>`.

Add to `app/helpers/tax_years_helper.rb`:

```ruby
  def can_edit_adjustments?(person_id) = Current.user.household_owner? || Current.user.person&.id == person_id
```

In `app/views/tax_years/_breakdown.html.erb`, fill the empty last cell of the person rows:

```erb
        <td><%= link_to "Adjustments", edit_person_adjustment_path(line.person.id, @year) if can_edit_adjustments?(line.person.id) %></td>
```

- [ ] **Step 5: Run, rubocop, commit**

Run: `bundle exec rspec spec/requests/person_adjustments_spec.rb spec/requests/people_spec.rb spec/requests/tax_years_spec.rb` → PASS; `bin/rubocop` clean.

```bash
git add app config spec
git commit -m "Tax engine: per-person health insurance and retirement adjustments

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Dashboard card

**Files:**
- Modify: `app/controllers/dashboards_controller.rb`, `app/views/dashboards/show.html.erb`
- Test: `spec/requests/tax_dashboard_spec.rb`

**Interfaces:**
- Consumes: `Tax.estimate`, partial `tax_years/_due_card` (Task 9).

- [ ] **Step 1: Write the failing request spec**

`spec/requests/tax_dashboard_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Estimated tax on the dashboard" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }
  let!(:owner) { create(:user, :household_owner).tap { create(:membership, user: _1, business:, role: "owner") } }

  around { |example| travel_to(Date.new(2026, 5, 1)) { example.run } }

  it "shows the next installment with the IRS link and a link to the taxes page" do
    create(:tax_parameters, :federal_2026)
    sign_in_as owner
    get root_path
    card = Nokogiri::HTML(response.body).at_css(".tax-due")
    expect(card.text).to include("Pay at least").and include("Jun 15, 2026")
    expect(card.at_css("a[target='_blank']")["href"]).to eq(Household::DEFAULT_IRS_PAYMENT_URL)
    expect(card.at_css("a[href='#{tax_year_path(2026)}']")).to be_present
  end

  it "is hidden when the year's federal figures are incomplete" do
    create(:tax_parameters)
    sign_in_as owner
    get root_path
    expect(response.body).not_to include("tax-due")
  end

  it "is hidden from a user without household access" do
    create(:tax_parameters, :federal_2026)
    other = create(:business, household:)
    sign_in_as user_with_role("owner", other)
    get root_path
    expect(response.body).not_to include("tax-due")
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/requests/tax_dashboard_spec.rb`
Expected: the first example FAILS (no card).

- [ ] **Step 3: Implement**

In `DashboardsController#show`, add:

```ruby
    @tax_estimate = Tax.estimate(household: Household.instance, year: Date.current.year) if Current.user.can_view_household?
```

In `app/views/dashboards/show.html.erb`, right after the sales tax card block:

```erb
<% if @tax_estimate %>
  <%= render "tax_years/due_card", estimate: @tax_estimate, household: Household.instance, show_page_link: true %>
<% end %>
```

- [ ] **Step 4: Run, rubocop, commit**

Run: `bundle exec rspec spec/requests/tax_dashboard_spec.rb spec/requests/household_dashboard_spec.rb` → PASS; `bin/rubocop` clean.

```bash
git add app spec
git commit -m "Tax engine: next estimated tax card on the dashboard

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Demo data

**Files:**
- Modify: `lib/demo_seeder.rb`, `spec/lib/demo_seeder_spec.rb`

**Interfaces:**
- Consumes: Tasks 1–6 models, `Tax::DueDates`, `Tax.estimate`.

- [ ] **Step 1: Write the failing spec**

Add to `spec/lib/demo_seeder_spec.rb` (its `today` is `Date.new(2026, 10, 5)`, so Apr 15, Jun 15, and Sep 15 have passed):

```ruby
  it "seeds a tax year with every past installment paid from joint checking" do
    load Rails.root.join("db/seeds.rb")
    run
    household = Household.instance
    tax_year = household.tax_years.find_by!(year: 2026)
    expect(tax_year.prior_year).to be_present
    payments = tax_year.estimated_payments.order(:quarter)
    expect(payments.map(&:quarter)).to eq([ 1, 2, 3 ])
    expect(payments.map { _1.debit.payee }).to all(eq("IRS USATAXPYMT"))
    expect(payments.map { _1.debit.account.name }).to all(eq("Joint Checking"))
    expect(HomeOffice.find_by!(business: Business.find_by!(name: "Sound Roots Productions"), year: 2026)).to be_present
    expect(PersonAdjustment.where(year: 2026).count).to eq(2)
    estimate = Tax.estimate(household:, year: 2026, today:)
    expect(estimate.quarter).to eq(4)
    expect(estimate.next_due_on).to eq(Date.new(2027, 1, 15))
  end

  it "copies every federal figure when it fills in a missing year" do
    load Rails.root.join("db/seeds.rb")
    run
    expect(TaxParameters.for_year(2025)).to be_estimate_ready
  end
```

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb`
Expected: the two new examples FAIL.

- [ ] **Step 3: Implement**

In `DemoSeeder#build`, keep the locals for both people (`alex_person`, `whitney_person`) and add as the last line: `seed_taxes(household, sound_roots, alex_person, whitney_person)`.

Add the method (after `seed_plaid`):

```ruby
  # Federal estimated tax for this year: last year's figures, a home office, adjustments for both people, and every installment
  # already due paid from Joint Checking through IRS Direct Pay, so the next one shows as due.
  def seed_taxes(household, business, owner_person, spouse_person)
    year = @today.year
    tax_year = household.tax_years.create!(year: year, prior_year_total_tax_cents: 2_400_000, prior_year_agi_cents: 11_800_000)
    business.home_offices.create!(year: year, calculation: "simplified", office_sqft: 200)
    owner_person.person_adjustments.create!(year: year, se_health_insurance_cents: 720_000)
    spouse_person.person_adjustments.create!(year: year, retirement_contribution_cents: 600_000, retirement_plan: "sep")

    joint = household.personal_book.accounts.find_by!(name: "Joint Checking")
    other = household.personal_book.categories.find_by!(name: "Other")
    Tax::DueDates.for(year).each_with_index do |due_on, index|
      next if due_on > @today

      debit = joint.transactions.create!(posted_on: due_on, payee: "IRS USATAXPYMT", memo: "Federal estimated tax", amount_cents: -600_000,
                                         category: other, categorized_by: "user", external_id: "demo-irs-#{year}-q#{index + 1}")
      tax_year.estimated_payments.new.tap { _1.link(debit) }.save!
    end
  end
```

In `ensure_tax_parameters`, replace the copy branch so a filled year gets every column, not just the mileage rate:

```ruby
      if latest_params
        TaxParameters.create!(latest_params.attributes.except("id", "year", "created_at", "updated_at").merge("year" => year))
        @out.puts "Demo: copied #{latest_params.year} tax parameters to #{year}"
```

(The existing spec matches `"Demo: copied"`, which this keeps.)

- [ ] **Step 4: Run, rubocop, commit**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb` → PASS; `bin/rails demo:reset` → finishes without errors; `bin/rubocop` clean.

```bash
git add lib spec
git commit -m "Tax engine: demo tax year, home office, adjustments, and linked IRS payments

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: End-to-end check, docs, PR

**Files:**
- Modify: `README.md`, `docs/roadmap.md`

- [ ] **Step 1: README**

In `README.md`, after the Sales tax paragraph, add:

> **Federal estimated tax.** The **Taxes** page (household access) estimates each quarter's federal payment for a married-filing-jointly household of sole proprietors: SE tax per person, Additional Medicare, AGI with half SE tax, self-employed health insurance, and retirement contributions, the standard deduction, a simplified QBI deduction, and the brackets. It shows the regular installment (against the lesser of 90% of projected tax and the 100%/110% prior-year safe harbor) beside the annualized installment (Form 2210 Schedule AI) and recommends the lesser, with every intermediate number in a worksheet. Payments are recorded by picking the IRS debit from the bank feed. Home office (simplified or regular) fills Schedule C line 30. The federal figures live in **Tax parameters** (2026 seeded), and the IRS payment link in **Household** settings. It's an estimate; verify with your accountant.

- [ ] **Step 2: Full verification**

Run each and confirm clean output:
- `bundle exec rspec` → all examples, 0 failures, nothing else printed
- `bin/rubocop`
- `bin/brakeman --no-pager`
- `bin/bundler-audit`
- `bin/importmap audit`

- [ ] **Step 3: Rebase check against Goals**

`git fetch origin`. If Goals has merged into `main`: `git rebase origin/main`, resolve conflicts in `db/schema.rb` (re-run `bin/rails db:migrate`), `lib/demo_seeder.rb`, the dashboard, `config/routes.rb`, `app/helpers/navigation_helper.rb`, and `docs/roadmap.md`, keeping both sides' additions, then re-run Step 2. Otherwise skip.

- [ ] **Step 4: Commit, push, open the PR**

Update `docs/roadmap.md`: sub-project 6's Status → `In review (PR #N)` once the PR number is known, its `○` → `◐` in the dependency graph.

```bash
git add README.md docs/roadmap.md
git commit -m "Tax engine: README and roadmap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin tax-engine
gh pr create --base main --title "Tax engine (sub-project 6)" --body-file <body>
```

The PR body has a Summary, the spec and plan paths, the **Acceptance testing** steps below, and ends with:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

After the PR exists, amend the roadmap commit with the PR number and push again.

Acceptance testing (put the same steps in the PR body and the GB-6 Kaneo task description):

1. `bin/rails demo:reset`, `bin/dev`; log in as `alex@example.com` (password and TOTP secret printed by the reset).
2. Dashboard: an "Estimated tax" card says "Pay at least $… by Jan 15, 2027" (or the next due date for today), with **Pay on IRS.gov ↗** and a link to the taxes page. Click the IRS link: IRS Direct Pay opens in a new tab.
3. Sidebar → Taxes: the 2026 page shows the due card, the four-quarter table (Q1–Q3 paid $6,000.00 each), the Businesses and Self-employment tax tables, and the payment log with three "IRS USATAXPYMT · Joint Checking" rows.
4. Click Q2 in the table: the worksheet title reads "Worksheet for Q2 (annualized ×2.4)" and the Annualized column shows "—" for Q3 and Q4. Open the worksheet: business profit, home office used, SE earnings, half SE tax, health insurance, retirement, AGI, standard deduction, QBI, each bracket, total, 90%, safe harbor ($24,000.00: 100% of the prior year's tax, because the demo's prior AGI of $118,000 is under $150,000), and required.
5. Prior-year figures → clear both fields and save → the "Enter last year's total tax and AGI…" banner appears and safe harbor shows "—". Restore $24,000 / $118,000.
6. Record a payment → search "KROGER" → Use this on a grocery debit → it records; delete it from the log. Then Record a payment → "Or enter it by hand": Jan 10, 2027, $500, Quarter "From the date" → it lands in Q4.
7. Sound Roots Productions → Reports → Schedule C 2026: line 30 shows $1,000.00 (200 sq ft × $5), "Tentative profit (line 29)" above it, net profit below. Edit home office → Regular, office 300, home 200 → "must be at least the office's square feet".
8. People → Whitney → Tax adjustments: set a SEP contribution of $50,000 → on the taxes page a warning says it's over the estimated limit.
9. Settings → Household: change the IRS payment site to `https://www.irs.gov/payments` → the taxes page and dashboard links use it. Try `http://example.com` → error.
10. Settings → Tax parameters → 2026: every federal field is filled; the bracket table has seven rows plus two blank ones. Add `/taxes/2027`: "Federal tax figures for 2027 are incomplete." with a link to enter them.
11. Log in as `whitney@example.com`: Taxes is visible (viewer of Sound Roots, editor of her own); she can open her own Tax adjustments but gets 403 on Alex's; no Record payment, Prior-year figures, or Home office links for Sound Roots.
12. Log in as `accountant@example.com`: the taxes page is readable; the payment log says "Linked to a bank transaction" instead of the IRS payee; `/taxes/2026/edit` → 403; `/taxes/2026/payments/new` → 403.

- [ ] **Step 5: Get CI green and update Kaneo**

Watch `gh pr checks --watch` and fix anything red. Then move GB-6 to In Review with a comment linking the PR, and put the acceptance steps in its description.

---

## Summary

| Task | Delivers |
|---|---|
| 1 | `PercentAttribute` (shared with sales tax), federal `TaxParameters` columns, published 2026 figures, seeds |
| 2 | Tax parameters form with federal fields and bracket rows |
| 3 | Pure `Tax::DueDates`, `Tax::Brackets`, `Tax::HomeOfficeDeduction` |
| 4 | Pure `Tax::PeriodCalculator` and the input structs |
| 5 | Pure `Tax::Estimator`: installments, safe harbor, warnings |
| 6 | `TaxYear`, `EstimatedPayment`, `HomeOffice`, `PersonAdjustment`, `Household#irs_payment_url` |
| 7 | `Tax::Inputs.load`, `Tax.estimate`, Schedule C line 30 math |
| 8 | Household settings page |
| 9 | Taxes page: due card, installments, breakdown, worksheet, payment log, prior-year form |
| 10 | Recording payments: debit picker, manual entry, edit, delete, system spec |
| 11 | Home office form, Schedule C line 30, taxes page link |
| 12 | Per-person adjustments |
| 13 | Dashboard card |
| 14 | Demo data |
| 15 | README, verification, PR, acceptance steps |
