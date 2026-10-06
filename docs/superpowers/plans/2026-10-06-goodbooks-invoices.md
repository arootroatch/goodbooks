# goodbooks Invoices (Sub-project 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track what each business's clients owe and link each payment to the deposit that paid it — clients, invoices, payments (from the invoice page and from the inbox), aging, CSV exports, demo data — delivered in a PR where every CI check passes.

**Architecture:** Same shape as Core. Pure objects (`Invoices::Allocation`, `Invoices::NumberSuggester`, `Reports::InvoiceAging`) hold the arithmetic and are unit-tested without the DB. One service, `InvoicePayments` (`link` / `unlink`), is the only writer of payments; it locks the invoice and deposit rows and calls `Invoice#sync_payment_status!`, the single place that moves an invoice between `sent` and `paid`. Controllers stay thin, go through `BusinessScoped`, and resolve every foreign key (`client_id`, `deposit_id`, `category_id`) through the business so other businesses' records are 404.

**Tech Stack:** Ruby 4.0.7, Rails 8.1.4, SQLite, Hotwire (Turbo streams for the inbox), Active Storage (local disk, public routes disabled), RSpec, FactoryBot, Capybara (rack_test; Selenium headless Chrome for `js: true`), Brakeman, bundler-audit, RuboCop (rails-omakase), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-06-goodbooks-invoices-design.md` (parent: `docs/superpowers/specs/2026-10-05-goodbooks-design.md` §3 cross-cutting rules).

## Prerequisites (before Task 1)

- Ruby 4.0.7 must be on `PATH` (`ruby -v` → `ruby 4.0.7`). Core used `~/.rubies/ruby-4.0.7`; as of 2026-10-06 that directory does not exist on the dev Mac (only 3.3.6 is installed). Install it the way the user chooses (e.g. `ruby-install ruby 4.0.7` into `~/.rubies`) **after confirming with the user**, then prefix every command with `export PATH="$HOME/.rubies/ruby-4.0.7/bin:$PATH"`.
- `bundle install`, `bin/rails db:prepare`, then `bundle exec rspec` → `436 examples, 0 failures` with no other output. This is the baseline; if it is not green, stop and report.
- Work on branch `invoices` (already created; it holds the spec commits).

## Global Constraints

- Ruby 4.0.7, Rails `~> 8.1.4`, SQLite only.
- Money is signed integer cents in `*_cents` columns; display with the `money(cents)` helper; parse human input with `Money.parse` (raises `Money::ParseError`) or the `money_attribute` concern. Never floats.
- `Transaction#amount_cents`: positive = money in. A deposit is a transaction with `amount_cents > 0`.
- Never name an association, method, or local `transaction`. The payment's link to its deposit is `InvoicePayment#deposit` (column `deposit_id` → `transactions`). DB transactions use `ApplicationRecord.transaction`.
- Non-member → 404 (records looked up through `@business` or `Transaction.for_businesses(@business.id)`). Viewer writing → 403 (`require_editor!`). Household screens → 404 unless `Current.user.can_view_household?` (`require_household_access!`).
- Strong params never list a `*_id` key. Read `client_id`, `deposit_id`, `category_id` as scalars from `params` and resolve them through the business. Query-string filters go through `ScalarParams#scalar_params` (Task 1), never `permit`.
- Only `InvoicePayments.link` / `.unlink` create or destroy `InvoicePayment` rows (factories in specs excepted). Only `Invoice#sync_payment_status!` sets `paid` / `paid_on`.
- Invoice status is one of `draft sent paid void`. Display statuses add `partial` and `overdue` (derived, never stored). Due today is **not** overdue; due yesterday is 1 day past due.
- Test output must stay clean: a passing `bundle exec rspec` prints only the reporter. Deprecations raise in test.
- TDD: each task writes its failing spec first and runs it to see it fail.
- `config.action_controller.raise_on_missing_callback_actions = true` in test: every `only:`/`except:` list must name existing actions.
- Formatting: single spaces in literals, no column alignment. `bin/rubocop` must pass after every task.
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01VdQWdubZ6L19ekyi7gz8GK
  ```
- Kaneo: the controlling session (not task implementers) comments progress on task GB-3 ("Phase 2: Invoices", project GoodBooks, workspace Root User Projects) after each task and moves it to In Review when the PR opens.

## Review Focus

1. **Double submits and stale pages**: clicking "Mark paid" or "Link" twice, or linking a deposit another tab already allocated, must be rejected with a clear flash ("That deposit is already linked to this invoice." / "This deposit is already fully allocated."), never over-allocate, never 500. (Pinned in Tasks 6 and 11.)
2. **Changing a linked deposit by any route** — transaction edit form, crafted classification request (transfer/exclude/expense category), manual delete, lowering a manual deposit's amount — is refused with "Linked to INV-… — unlink the payment first." and the invoice stays paid. (Pinned in Task 5.)
3. **Due-date and aging boundaries**: due today → not overdue, bucket Current; 1 day → 1–30; 30 → 1–30; 31 → 31–60; 60 → 31–60; 61 → Over 60. (Pinned in Tasks 3 and 4.)
4. **Money typed by humans** in the invoice amount and the payment amount fields (`$1,200.00`, `1,200`, `0`, `-5`, `abc`) parses exactly or produces a validation error/flash; it never creates a $0 invoice or a $0 payment. (Pinned in Tasks 4 and 10.)
5. **Foreign IDs from another business** (`client_id`, `deposit_id`, `category_id`, an invoice or PDF URL) → 404, and a viewer's crafted POST/PATCH/DELETE to every new write endpoint → 403. (Pinned in Tasks 7–11.)

## File Map

```
.github/workflows/ci.yml                          + test job (Task 1)
app/controllers/concerns/scalar_params.rb         scalar query-string filters (Task 1)
app/models/invoices/allocation.rb                 pure: payment amount rules (Task 2)
app/models/invoices/number_suggester.rb           pure: next invoice number (Task 2)
app/models/reports/invoice_aging.rb               pure: aging buckets (Task 3)
db/migrate/*_create_{clients,invoices,invoice_payments}.rb (Task 4)
app/models/{client,invoice,invoice_payment}.rb    (Task 4; pdf in Task 9; receivables in Task 13)
app/models/transaction.rb                         linked-deposit guards + scopes (Task 5)
app/services/invoice_payments.rb                  link / unlink (Task 6)
app/controllers/clients_controller.rb + views     (Task 7)
app/models/invoice_filter.rb                      list filtering (Task 8)
app/controllers/invoices_controller.rb + views, app/helpers/invoices_helper.rb (Task 8)
app/controllers/invoice_pdfs_controller.rb        (Task 9)
app/controllers/invoice_payments_controller.rb + views (Tasks 10–11)
app/models/invoice_matcher.rb, app/views/inboxes/_invoice_hint.html.erb (Task 11)
app/models/reports/{invoice_csv,invoice_aging_csv}.rb (Task 12)
app/controllers/{invoice_agings,household_invoices,household_invoice_agings}_controller.rb (Task 12)
app/views/invoices/_receivables.html.erb          (Task 13)
lib/demo_seeder.rb                                (Task 14)
```

---

### Task 1: CI green: Brakeman fix, test job, bundler-audit

**Files:**
- Create: `app/controllers/concerns/scalar_params.rb`
- Modify: `app/controllers/transactions_controller.rb` (`filter_params`, include)
- Modify: `.github/workflows/ci.yml` (add `test` job)
- Modify (only if bundler-audit reports advisories): `Gemfile.lock`
- Test: `spec/requests/transaction_filters_spec.rb`

**Interfaces:**
- Produces: `ScalarParams#scalar_params(*keys) → Hash{Symbol => String}` (private; only keys whose value is a non-blank `String`). Used by `TransactionsController` and later `InvoicesController` / `HouseholdInvoicesController`.

Why: Brakeman (CI `scan_ruby`) fails with a high-confidence Mass Assignment warning on `params.permit(..., :account_id, ...)` at `app/controllers/transactions_controller.rb:62`. These are list filters on an already business-scoped relation, so nothing is mass-assigned; reading them as scalars removes the `permit` call and the warning, and also drops array/hash values a crafted URL could send.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/requests/transaction_filters_spec.rb
require "rails_helper"

RSpec.describe "Transaction list filters" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business) }
  let!(:mine) { create(:transaction, account: account, payee: "My own payee") }
  let!(:other_account) { create(:account) }
  let!(:theirs) { create(:transaction, account: other_account, payee: "Other business payee") }

  before { sign_in_as user_with_role("viewer", business) }

  it "never shows another business's transactions when filtering by its account" do
    get business_transactions_path(business, account_id: other_account.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Other business payee")
    expect(response.body).not_to include("My own payee")
  end

  it "ignores non-scalar filter values" do
    get business_transactions_path(business, account_id: [ account.id ], q: { "x" => "y" })
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("My own payee")
  end

  it "still filters by its own account" do
    get business_transactions_path(business, account_id: account.id)
    expect(response.body).to include("My own payee")
  end
end
```

- [ ] **Step 2: Run it and Brakeman to see both fail**

Run: `bin/brakeman --no-pager -q`
Expected: exit code 3, `Mass Assignment` on `transactions_controller.rb`. **This is the failing check for this task.**
Run: `bundle exec rspec spec/requests/transaction_filters_spec.rb`
Expected: these may already pass under `permit` (it also drops non-scalars). They pin the behavior so the refactor in Step 3 cannot regress it; if any fails, note which and why before continuing.

- [ ] **Step 3: Add the concern and use it**

```ruby
# app/controllers/concerns/scalar_params.rb
module ScalarParams
  private

  # Query-string filters are matched against already-scoped relations, never mass-assigned,
  # so they are read as plain strings instead of going through `permit`.
  def scalar_params(*keys)
    keys.index_with { params[_1] }.select { |_, value| value.is_a?(String) && value.present? }
  end
end
```

In `app/controllers/transactions_controller.rb`, add `include ScalarParams` under `include BusinessScoped`, and replace `filter_params`:

```ruby
  def filter_params
    scalar_params(:from, :to, :account_id, :category_id, :status, :q, :page)
  end
```

- [ ] **Step 4: Run the spec, the transactions specs, and Brakeman**

Run: `bundle exec rspec spec/requests/transaction_filters_spec.rb spec/requests/transactions_spec.rb spec/models/transaction_filter_spec.rb`
Expected: all pass.
Run: `bin/brakeman --no-pager -q`
Expected: `No warnings found`, exit 0.

- [ ] **Step 5: Run bundler-audit**

Run: `bin/bundler-audit`
Expected: `No vulnerabilities found`. If it lists advisories: for each gem run `bundle update --conservative <gem>`, rerun `bin/bundler-audit` until clean, then run the full suite (`bundle exec rspec`) to prove the update broke nothing. Record each bumped gem and advisory ID in the commit message.

- [ ] **Step 6: Add the test job to CI**

Append to `.github/workflows/ci.yml` under `jobs:` (same indentation as `lint:`):

```yaml
  test:
    runs-on: ubuntu-latest
    env:
      RAILS_ENV: test
    steps:
      - name: Checkout code
        uses: actions/checkout@v6

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Prepare database
        run: bin/rails db:test:prepare

      - name: Run specs (system specs use the runner's preinstalled Chrome)
        run: bundle exec rspec
```

If the `test` job later fails in CI because Chrome or chromedriver is missing (Task 15 checks), add before "Prepare database":

```yaml
      - name: Set up Chrome
        uses: browser-actions/setup-chrome@v2
        with:
          install-chromedriver: true
```

- [ ] **Step 7: Full local check and commit**

Run: `bundle exec rspec && bin/rubocop && bin/brakeman --no-pager -q && bin/bundler-audit && bin/importmap audit`
Expected: 439 examples, 0 failures, clean output; RuboCop no offenses; Brakeman no warnings; no vulnerabilities.

```bash
git add app/controllers/concerns/scalar_params.rb app/controllers/transactions_controller.rb spec/requests/transaction_filters_spec.rb .github/workflows/ci.yml Gemfile.lock
git commit -m "CI: read transaction filters as scalars (Brakeman), add RSpec job"
```

---

### Task 2: Pure allocation rules and invoice number suggestion

**Files:**
- Create: `app/models/invoices/allocation.rb`
- Create: `app/models/invoices/number_suggester.rb`
- Test: `spec/models/invoices/allocation_spec.rb`, `spec/models/invoices/number_suggester_spec.rb`

**Interfaces:**
- Produces: `Invoices::Allocation.call(invoice_amount_cents:, invoice_paid_cents:, deposit_amount_cents:, deposit_allocated_cents:, requested_cents: nil) → Invoices::Allocation::Result` with `#amount_cents` (Integer or nil), `#error` (String or nil), `#ok?`.
- Produces: `Invoices::NumberSuggester.next(numbers) → String` (`numbers`: Array of String).

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/models/invoices/allocation_spec.rb
require "rails_helper"

RSpec.describe Invoices::Allocation do
  def call(requested = nil, invoice: 120_000, paid: 0, deposit: 120_000, allocated: 0)
    described_class.call(invoice_amount_cents: invoice, invoice_paid_cents: paid,
                         deposit_amount_cents: deposit, deposit_allocated_cents: allocated, requested_cents: requested)
  end

  it "proposes the full amount for an exact match" do
    result = call
    expect(result).to be_ok
    expect(result.amount_cents).to eq(120_000)
  end

  it "proposes the invoice's outstanding balance when the deposit is larger" do
    expect(call(invoice: 120_000, paid: 20_000, deposit: 500_000).amount_cents).to eq(100_000)
  end

  it "proposes the deposit's unallocated amount when the invoice is larger" do
    expect(call(invoice: 300_000, deposit: 100_000, allocated: 40_000).amount_cents).to eq(60_000)
  end

  it "accepts a smaller requested amount (partial payment)" do
    expect(call(50_000).amount_cents).to eq(50_000)
  end

  it "accepts a request equal to both limits" do
    expect(call(120_000)).to be_ok
  end

  it "rejects a fully paid invoice" do
    expect(call(paid: 120_000).error).to eq("This invoice is already fully paid.")
  end

  it "rejects a fully allocated deposit" do
    expect(call(allocated: 120_000).error).to eq("This deposit is already fully allocated.")
  end

  it "rejects zero and negative requests" do
    expect(call(0).error).to eq("Amount must be greater than zero.")
    expect(call(-5).error).to eq("Amount must be greater than zero.")
  end

  it "rejects a request above the invoice's outstanding balance" do
    expect(call(100_001, invoice: 100_000, deposit: 500_000).error)
      .to eq("Amount can't exceed the invoice's outstanding $1,000.00.")
  end

  it "rejects a request above the deposit's unallocated amount" do
    expect(call(90_000, invoice: 500_000, deposit: 100_000, allocated: 20_000).error)
      .to eq("Amount can't exceed the deposit's unallocated $800.00.")
  end
end
```

```ruby
# spec/models/invoices/number_suggester_spec.rb
require "rails_helper"

RSpec.describe Invoices::NumberSuggester do
  it "starts at 1001" do
    expect(described_class.next([])).to eq("1001")
  end

  it "increments the highest number, keeping prefix and zero padding" do
    expect(described_class.next(%w[INV-0009 INV-0042 INV-0010])).to eq("INV-0043")
  end

  it "grows past the padding width" do
    expect(described_class.next(%w[A-9])).to eq("A-10")
    expect(described_class.next(%w[99])).to eq("100")
  end

  it "ignores numbers without trailing digits" do
    expect(described_class.next(%w[DRAFT 2026-007])).to eq("2026-008")
    expect(described_class.next(%w[DRAFT])).to eq("1001")
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/invoices`
Expected: FAIL with `uninitialized constant Invoices`.

- [ ] **Step 3: Implement**

```ruby
# app/models/invoices/allocation.rb
module Invoices
  module Allocation
    Result = Data.define(:amount_cents, :error) do
      def ok? = error.nil?
    end

    def self.call(invoice_amount_cents:, invoice_paid_cents:, deposit_amount_cents:, deposit_allocated_cents:, requested_cents: nil)
      outstanding = invoice_amount_cents - invoice_paid_cents
      unallocated = deposit_amount_cents - deposit_allocated_cents
      return failure("This invoice is already fully paid.") unless outstanding.positive?
      return failure("This deposit is already fully allocated.") unless unallocated.positive?
      return success([ outstanding, unallocated ].min) if requested_cents.nil?
      return failure("Amount must be greater than zero.") unless requested_cents.positive?
      return failure("Amount can't exceed the invoice's outstanding #{Money.new(outstanding)}.") if requested_cents > outstanding
      return failure("Amount can't exceed the deposit's unallocated #{Money.new(unallocated)}.") if requested_cents > unallocated

      success(requested_cents)
    end

    def self.success(cents) = Result.new(amount_cents: cents, error: nil)
    def self.failure(message) = Result.new(amount_cents: nil, error: message)
    private_class_method :success, :failure
  end
end
```

```ruby
# app/models/invoices/number_suggester.rb
module Invoices
  module NumberSuggester
    FIRST = "1001"

    def self.next(numbers)
      parsed = numbers.filter_map { |number| number.to_s.match(/\A(.*?)(\d+)\z/)&.captures }
      return FIRST if parsed.empty?

      prefix, digits = parsed.max_by { |_, d| d.to_i }
      "#{prefix}#{(digits.to_i + 1).to_s.rjust(digits.length, "0")}"
    end
  end
end
```

- [ ] **Step 4: Run them to see them pass**

Run: `bundle exec rspec spec/models/invoices && bin/rubocop app/models/invoices spec/models/invoices`
Expected: all pass, no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/models/invoices spec/models/invoices
git commit -m "Invoices: pure allocation rules and number suggestion"
```

---

### Task 3: Pure aging buckets

**Files:**
- Create: `app/models/reports/invoice_aging.rb`
- Test: `spec/models/reports/invoice_aging_spec.rb`

**Interfaces:**
- Produces: `Reports::InvoiceAging::Row = Data.define(:invoice_id, :number, :client_name, :business_name, :due_date, :outstanding_cents)`.
- Produces: `Reports::InvoiceAging.new(rows, as_of:)` with `#buckets → [Bucket]` (always 4, in order `current`, `days_1_30`, `days_31_60`, `over_60`), `Bucket = Data.define(:key, :label, :rows, :total_cents)`, `#total_cents`, and `.days_past_due(due_date, as_of) → Integer` (0 when not past due).
- Produces: `Reports::InvoiceAging.rows_from(invoices) → [Row]` (maps loaded `Invoice` records; used by Task 12).

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/models/reports/invoice_aging_spec.rb
require "rails_helper"

RSpec.describe Reports::InvoiceAging do
  let(:as_of) { Date.new(2026, 10, 6) }

  def row(days_past_due, cents = 10_000, number: "INV-#{days_past_due}", business: "Pat Consulting")
    Reports::InvoiceAging::Row.new(invoice_id: days_past_due, number: number, client_name: "Acme",
                                   business_name: business, due_date: as_of - days_past_due, outstanding_cents: cents)
  end

  def bucket_for(days)
    described_class.new([ row(days) ], as_of: as_of).buckets.find { _1.rows.any? }.key
  end

  it "puts each boundary day in the right bucket" do
    expect(bucket_for(-5)).to eq("current")
    expect(bucket_for(0)).to eq("current")
    expect(bucket_for(1)).to eq("days_1_30")
    expect(bucket_for(30)).to eq("days_1_30")
    expect(bucket_for(31)).to eq("days_31_60")
    expect(bucket_for(60)).to eq("days_31_60")
    expect(bucket_for(61)).to eq("over_60")
  end

  it "always returns the four buckets in order with labels" do
    report = described_class.new([], as_of: as_of)
    expect(report.buckets.map(&:key)).to eq(%w[current days_1_30 days_31_60 over_60])
    expect(report.buckets.map(&:label)).to eq([ "Current", "1–30 days", "31–60 days", "Over 60 days" ])
    expect(report.total_cents).to eq(0)
  end

  it "totals each bucket and the report, oldest due first within a bucket" do
    report = described_class.new([ row(5, 1_000), row(20, 2_000), row(45, 4_000), row(90, 8_000) ], as_of: as_of)
    one_to_thirty = report.buckets.find { _1.key == "days_1_30" }
    expect(one_to_thirty.rows.map(&:number)).to eq(%w[INV-20 INV-5])
    expect(one_to_thirty.total_cents).to eq(3_000)
    expect(report.total_cents).to eq(15_000)
  end

  it "counts days past due" do
    expect(described_class.days_past_due(as_of - 12, as_of)).to eq(12)
    expect(described_class.days_past_due(as_of, as_of)).to eq(0)
    expect(described_class.days_past_due(as_of + 3, as_of)).to eq(0)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/models/reports/invoice_aging_spec.rb`
Expected: FAIL with `uninitialized constant Reports::InvoiceAging`.

- [ ] **Step 3: Implement**

```ruby
# app/models/reports/invoice_aging.rb
module Reports
  class InvoiceAging
    Row = Data.define(:invoice_id, :number, :client_name, :business_name, :due_date, :outstanding_cents)
    Bucket = Data.define(:key, :label, :rows, :total_cents)
    BUCKETS = [ [ "current", "Current" ], [ "days_1_30", "1–30 days" ], [ "days_31_60", "31–60 days" ], [ "over_60", "Over 60 days" ] ].freeze

    attr_reader :buckets, :total_cents

    def self.days_past_due(due_date, as_of) = [ (as_of - due_date).to_i, 0 ].max

    def self.bucket_key(days)
      if days <= 0 then "current"
      elsif days <= 30 then "days_1_30"
      elsif days <= 60 then "days_31_60"
      else "over_60"
      end
    end

    def self.rows_from(invoices)
      invoices.map do |invoice|
        Row.new(invoice_id: invoice.id, number: invoice.number, client_name: invoice.client.name,
                business_name: invoice.business.name, due_date: invoice.due_date, outstanding_cents: invoice.outstanding_cents)
      end
    end

    def initialize(rows, as_of:)
      grouped = rows.group_by { self.class.bucket_key(self.class.days_past_due(_1.due_date, as_of)) }
      @buckets = BUCKETS.map do |key, label|
        list = (grouped[key] || []).sort_by { [ _1.due_date, _1.number ] }
        Bucket.new(key: key, label: label, rows: list, total_cents: list.sum(&:outstanding_cents))
      end
      @total_cents = @buckets.sum(&:total_cents)
    end
  end
end
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec rspec spec/models/reports/invoice_aging_spec.rb && bin/rubocop app/models/reports/invoice_aging.rb spec/models/reports/invoice_aging_spec.rb`
Expected: pass, no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/models/reports/invoice_aging.rb spec/models/reports/invoice_aging_spec.rb
git commit -m "Reports: pure invoice aging buckets"
```

---
### Task 4: Clients, invoices, payments — schema and models

**Files:**
- Create: `db/migrate/20261007000001_create_clients.rb`, `db/migrate/20261007000002_create_invoices.rb`, `db/migrate/20261007000003_create_invoice_payments.rb`
- Create: `app/models/client.rb`, `app/models/invoice.rb`, `app/models/invoice_payment.rb`
- Modify: `app/models/business.rb` (associations)
- Create: `spec/factories/clients.rb`, `spec/factories/invoices.rb`, `spec/factories/invoice_payments.rb`
- Test: `spec/models/client_spec.rb`, `spec/models/invoice_spec.rb`, `spec/models/invoice_payment_spec.rb`

**Interfaces:**
- Consumes: `MoneyAttribute` (`money_attribute :amount` → `amount=` parses, `amount_cents` column), `Money`.
- Produces: `Client` (`business`, `invoices`, scope `active`, `#archived?`, `#archived`).
- Produces: `Invoice` — enum `status` (`draft sent paid void`, scopes `Invoice.sent` etc.), `belongs_to :business, :client`, `has_many :payments` (class `InvoicePayment`), `#paid_cents`, `#outstanding_cents`, `#partial?`, `#overdue?(today = Date.current)`, `#days_past_due(today = Date.current)`, `#display_status(today = Date.current) → "draft"|"sent"|"partial"|"overdue"|"paid"|"void"`, `#can_take_payment?`, `#apply_event(event) → Boolean` (`"mark_sent"`, `"void"`, `"reopen"`; errors on `errors[:base]`), `#sync_payment_status!`, `Invoice::EVENTS`.
- Produces: `InvoicePayment` (`invoice`, `deposit` → `Transaction`, `amount_cents`, `money_attribute :amount`).
- Produces: `Business#clients`, `Business#invoices`.
- Produces factories `:client`, `:invoice` (status `sent`, amount 120_000, issue 2026-01-01, due 2026-01-31), `:invoice_payment` (creates a matching positive deposit in the invoice's business).

- [ ] **Step 1: Write the migrations**

```ruby
# db/migrate/20261007000001_create_clients.rb
class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.text :notes
      t.datetime :archived_at
      t.timestamps
    end
    add_index :clients, %i[business_id name], unique: true
  end
end
```

```ruby
# db/migrate/20261007000002_create_invoices.rb
class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :business, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.string :number, null: false
      t.date :issue_date, null: false
      t.date :due_date, null: false
      t.integer :amount_cents, null: false
      t.text :description
      t.string :status, null: false, default: "sent"
      t.date :paid_on
      t.timestamps
    end
    add_index :invoices, %i[business_id number], unique: true
    add_index :invoices, %i[business_id status]
  end
end
```

```ruby
# db/migrate/20261007000003_create_invoice_payments.rb
class CreateInvoicePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :invoice_payments do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :deposit, null: false, foreign_key: { to_table: :transactions }
      t.integer :amount_cents, null: false
      t.timestamps
    end
    add_index :invoice_payments, %i[invoice_id deposit_id], unique: true
  end
end
```

Run: `bin/rails db:migrate && RAILS_ENV=test bin/rails db:test:prepare`
Expected: three tables created; `db/schema.rb` updated.

- [ ] **Step 2: Write factories and failing model specs**

```ruby
# spec/factories/clients.rb
FactoryBot.define do
  factory :client do
    business
    sequence(:name) { |n| "Client #{n}" }
  end
end
```

```ruby
# spec/factories/invoices.rb
FactoryBot.define do
  factory :invoice do
    business
    client { association(:client, business: business) }
    sequence(:number) { |n| "INV-#{1000 + n}" }
    issue_date { Date.new(2026, 1, 1) }
    due_date { Date.new(2026, 1, 31) }
    amount_cents { 120_000 }
    status { "sent" }
  end
end
```

```ruby
# spec/factories/invoice_payments.rb
FactoryBot.define do
  factory :invoice_payment do
    invoice
    deposit do
      business = invoice.business
      income = business.categories.find_by(kind: "income") || association(:category, :income, business: business)
      association(:transaction, account: association(:account, business: business), amount_cents: invoice.amount_cents,
                                payee: "CLIENT PAYMENT", category: income, categorized_by: "user")
    end
    amount_cents { invoice.amount_cents }
  end
end
```

```ruby
# spec/models/client_spec.rb
require "rails_helper"

RSpec.describe Client do
  it "requires a name unique within the business" do
    client = create(:client, name: "Acme")
    expect(build(:client, business: client.business, name: "Acme")).not_to be_valid
    expect(build(:client, name: "Acme")).to be_valid
    expect(build(:client, name: "")).not_to be_valid
  end

  it "accepts a blank email but rejects a malformed one" do
    expect(build(:client, email: "")).to be_valid
    expect(build(:client, email: "billing@acme.test")).to be_valid
    expect(build(:client, email: "not an email")).not_to be_valid
  end

  it "lists only active clients in the active scope" do
    active = create(:client)
    create(:client, business: active.business, archived_at: Time.current)
    expect(active.business.clients.active).to eq([ active ])
  end
end
```

```ruby
# spec/models/invoice_payment_spec.rb
require "rails_helper"

RSpec.describe InvoicePayment do
  let(:invoice) { create(:invoice) }

  it "requires a positive amount" do
    expect(build(:invoice_payment, invoice: invoice, amount_cents: 0)).not_to be_valid
    expect(build(:invoice_payment, invoice: invoice, amount_cents: -5)).not_to be_valid
  end

  it "requires the deposit to be in the invoice's business" do
    foreign = create(:transaction, amount_cents: 120_000)
    payment = build(:invoice_payment, invoice: invoice, deposit: foreign)
    expect(payment).not_to be_valid
    expect(payment.errors[:deposit]).to include("must belong to the invoice's business")
  end

  it "links a deposit to an invoice at most once" do
    payment = create(:invoice_payment, invoice: invoice, amount_cents: 10_000)
    expect(build(:invoice_payment, invoice: invoice, deposit: payment.deposit, amount_cents: 10_000)).not_to be_valid
  end
end
```

```ruby
# spec/models/invoice_spec.rb
require "rails_helper"

RSpec.describe Invoice do
  let(:business) { create(:business) }
  let(:today) { Date.new(2026, 10, 6) }

  describe "validation" do
    it "keeps numbers unique within a business only" do
      create(:invoice, business: business, number: "INV-1")
      expect(build(:invoice, business: business, number: "INV-1")).not_to be_valid
      expect(build(:invoice, number: "INV-1")).to be_valid
    end

    it "requires the due date on or after the issue date" do
      invoice = build(:invoice, issue_date: Date.new(2026, 2, 1), due_date: Date.new(2026, 1, 31))
      expect(invoice).not_to be_valid
      expect(invoice.errors[:due_date]).to include("can't be before the issue date")
      expect(build(:invoice, issue_date: Date.new(2026, 2, 1), due_date: Date.new(2026, 2, 1))).to be_valid
    end

    it "requires the client to be in the same business" do
      invoice = build(:invoice, business: business, client: create(:client))
      expect(invoice).not_to be_valid
      expect(invoice.errors[:client]).to include("must belong to this business")
    end

    it "parses typed amounts and rejects zero, negative, and junk" do
      expect(build(:invoice, amount: "$1,200.00").amount_cents).to eq(120_000)
      expect(build(:invoice, amount: "1,200").amount_cents).to eq(120_000)
      %w[0 -5 abc].each { |input| expect(build(:invoice, amount: input)).not_to be_valid, "accepted #{input}" }
    end

    it "can't drop below what has been paid" do
      payment = create(:invoice_payment, invoice: create(:invoice, business: business), amount_cents: 50_000)
      invoice = payment.invoice
      invoice.amount_cents = 49_999
      expect(invoice).not_to be_valid
      expect(invoice.errors[:amount]).to include("can't be less than the $500.00 already paid")
    end
  end

  describe "derived status" do
    it "is overdue only after the due date" do
      expect(build(:invoice, due_date: today).display_status(today)).to eq("sent")
      overdue = build(:invoice, due_date: today - 1)
      expect(overdue.display_status(today)).to eq("overdue")
      expect(overdue.days_past_due(today)).to eq(1)
      expect(build(:invoice, due_date: today).days_past_due(today)).to eq(0)
    end

    it "is partial when sent with some payment" do
      payment = create(:invoice_payment, invoice: create(:invoice, due_date: today + 10), amount_cents: 20_000)
      expect(payment.invoice.reload.display_status(today)).to eq("partial")
      expect(payment.invoice.outstanding_cents).to eq(100_000)
    end

    it "never shows drafts, paid, or void invoices as overdue" do
      %w[draft paid void].each do |status|
        expect(build(:invoice, status: status, due_date: today - 30).display_status(today)).to eq(status)
      end
    end
  end

  describe "#apply_event" do
    it "moves draft → sent, draft/sent → void, void → sent" do
      invoice = create(:invoice, status: "draft")
      expect(invoice.apply_event("mark_sent")).to be(true)
      expect(invoice.reload).to be_sent
      expect(invoice.apply_event("void")).to be(true)
      expect(invoice.reload).to be_void
      expect(invoice.apply_event("reopen")).to be(true)
      expect(invoice.reload).to be_sent
    end

    it "refuses events that don't apply to the current status" do
      invoice = create(:invoice, status: "sent")
      expect(invoice.apply_event("mark_sent")).to be(false)
      expect(invoice.errors[:base]).to include("This invoice can't be marked sent while it is sent.")
      expect(invoice.reload).to be_sent
    end

    it "refuses to void an invoice that has payments" do
      payment = create(:invoice_payment, amount_cents: 10_000)
      invoice = payment.invoice
      expect(invoice.apply_event("void")).to be(false)
      expect(invoice.errors[:base]).to include("Unlink its payments before voiding this invoice.")
      expect(invoice.reload).to be_sent
    end
  end

  describe "#sync_payment_status!" do
    it "marks paid on the latest deposit date when fully paid, and reverts when not" do
      invoice = create(:invoice, business: business, amount_cents: 100_000)
      first = create(:invoice_payment, invoice: invoice, amount_cents: 40_000)
      first.deposit.update!(posted_on: Date.new(2026, 3, 1))
      second = create(:invoice_payment, invoice: invoice, amount_cents: 60_000)
      second.deposit.update!(posted_on: Date.new(2026, 3, 9))

      invoice.sync_payment_status!
      expect(invoice.reload).to be_paid
      expect(invoice.paid_on).to eq(Date.new(2026, 3, 9))

      second.destroy!
      invoice.sync_payment_status!
      expect(invoice.reload).to be_sent
      expect(invoice.paid_on).to be_nil
    end

    it "leaves drafts and void invoices alone" do
      invoice = create(:invoice, status: "draft")
      invoice.sync_payment_status!
      expect(invoice.reload).to be_draft
    end
  end

  it "can't be destroyed while it has payments" do
    payment = create(:invoice_payment)
    expect(payment.invoice.destroy).to be(false)
    expect(Invoice.exists?(payment.invoice_id)).to be(true)
  end
end
```

- [ ] **Step 3: Run them to see them fail**

Run: `bundle exec rspec spec/models/client_spec.rb spec/models/invoice_spec.rb spec/models/invoice_payment_spec.rb`
Expected: FAIL with `uninitialized constant Client` (and Invoice, InvoicePayment).

- [ ] **Step 4: Implement the models**

```ruby
# app/models/client.rb
class Client < ApplicationRecord
  belongs_to :business
  has_many :invoices, dependent: :restrict_with_error

  scope :active, -> { where(archived_at: nil) }

  validates :name, presence: true, length: { maximum: 200 }, uniqueness: { scope: :business_id }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :notes, length: { maximum: 2_000 }

  def archived? = archived_at.present?
  def archived = archived?
end
```

```ruby
# app/models/invoice_payment.rb
class InvoicePayment < ApplicationRecord
  include MoneyAttribute

  money_attribute :amount

  belongs_to :invoice
  belongs_to :deposit, class_name: "Transaction", inverse_of: :invoice_payments

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :deposit_id, uniqueness: { scope: :invoice_id, message: "is already linked to this invoice" }
  validate :deposit_in_invoice_business

  private

  def deposit_in_invoice_business
    return if invoice.nil? || deposit.nil?

    errors.add(:deposit, "must belong to the invoice's business") if deposit.account.business_id != invoice.business_id
  end
end
```

```ruby
# app/models/invoice.rb
class Invoice < ApplicationRecord
  include MoneyAttribute

  EVENTS = {
    "mark_sent" => { from: %w[draft], to: "sent", verb: "marked sent" },
    "void" => { from: %w[draft sent], to: "void", verb: "voided" },
    "reopen" => { from: %w[void], to: "sent", verb: "reopened" }
  }.freeze

  money_attribute :amount

  belongs_to :business
  belongs_to :client
  has_many :payments, class_name: "InvoicePayment", dependent: :restrict_with_error

  enum :status, { draft: "draft", sent: "sent", paid: "paid", void: "void" }, validate: true

  validates :number, presence: true, length: { maximum: 50 }, uniqueness: { scope: :business_id }
  validates :issue_date, :due_date, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :description, length: { maximum: 2_000 }
  validate :due_on_or_after_issue
  validate :client_in_business
  validate :amount_covers_payments
  validate :no_void_with_payments

  def paid_cents = payments.loaded? ? payments.sum(&:amount_cents) : payments.sum(:amount_cents)
  def outstanding_cents = amount_cents.to_i - paid_cents
  def partial? = sent? && paid_cents.positive?
  def overdue?(today = Date.current) = sent? && due_date < today
  def days_past_due(today = Date.current) = overdue?(today) ? (today - due_date).to_i : 0
  def can_take_payment? = sent? && outstanding_cents.positive?

  def display_status(today = Date.current)
    if overdue?(today) then "overdue"
    elsif partial? then "partial"
    else status
    end
  end

  def apply_event(event)
    rule = EVENTS.fetch(event)
    unless rule[:from].include?(status)
      errors.add(:base, "This invoice can't be #{rule[:verb]} while it is #{status}.")
      return false
    end
    update(status: rule[:to])
  end

  # The only code that moves an invoice between sent and paid.
  def sync_payment_status!
    return if draft? || void?

    payments.reset
    if outstanding_cents.zero?
      update!(status: "paid", paid_on: payments.joins(:deposit).maximum("transactions.posted_on"))
    else
      update!(status: "sent", paid_on: nil)
    end
  end

  private

  def due_on_or_after_issue
    errors.add(:due_date, "can't be before the issue date") if issue_date && due_date && due_date < issue_date
  end

  def client_in_business
    errors.add(:client, "must belong to this business") if client && client.business_id != business_id
  end

  def amount_covers_payments
    return unless persisted? && amount_cents

    paid = payments.sum(:amount_cents)
    errors.add(:amount, "can't be less than the #{Money.new(paid)} already paid") if amount_cents < paid
  end

  def no_void_with_payments
    return unless persisted? && will_save_change_to_status?(to: "void") && payments.exists?

    errors.add(:base, "Unlink its payments before voiding this invoice.")
  end
end
```

In `app/models/business.rb`, after `has_many :mileage_entries, dependent: :destroy`:

```ruby
  has_many :clients, dependent: :restrict_with_error
  has_many :invoices, dependent: :restrict_with_error
```

`Transaction` needs the inverse association now (the guards come in Task 5). In `app/models/transaction.rb`, after `belongs_to :rule, optional: true`:

```ruby
  has_many :invoice_payments, foreign_key: :deposit_id, inverse_of: :deposit, dependent: :restrict_with_error
```

- [ ] **Step 5: Run the specs to see them pass, then the full suite**

Run: `bundle exec rspec spec/models/client_spec.rb spec/models/invoice_spec.rb spec/models/invoice_payment_spec.rb`
Expected: all pass.
Run: `bundle exec rspec && bin/rubocop`
Expected: 0 failures, clean output, no offenses.

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb app/models/client.rb app/models/invoice.rb app/models/invoice_payment.rb app/models/business.rb app/models/transaction.rb spec/factories spec/models/client_spec.rb spec/models/invoice_spec.rb spec/models/invoice_payment_spec.rb
git commit -m "Invoices: clients, invoices, payments schema and models"
```

---

### Task 5: Guard linked deposits

**Files:**
- Modify: `app/models/transaction.rb`
- Modify: `app/controllers/transactions_controller.rb` (`destroy`)
- Modify: `app/controllers/classifications_controller.rb` (`update`)
- Test: `spec/models/transaction_linked_deposit_spec.rb`, `spec/requests/linked_deposit_guards_spec.rb`, `spec/services/rule_applier_spec.rb` (add one example)

**Interfaces:**
- Consumes: `Transaction#invoice_payments` (Task 4), `Invoice#sync_payment_status!`.
- Produces: `Transaction::UNALLOCATED_SQL` (String SQL expression), scopes `Transaction.linkable_deposits` and `Transaction.with_unallocated(cents)`, `#allocated_cents`, `#unallocated_cents`, `#linked_invoice_message → String` ("Linked to INV-1, INV-2 — unlink the payment first.").

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/models/transaction_linked_deposit_spec.rb
require "rails_helper"

RSpec.describe Transaction, "linked to an invoice" do
  let(:payment) { create(:invoice_payment, invoice: create(:invoice, number: "INV-1042"), amount_cents: 120_000) }
  let(:deposit) { payment.deposit }
  let(:business) { deposit.business }
  let(:message) { "Linked to INV-1042 — unlink the payment first." }

  it "can't move to an expense category, be a transfer, or be excluded" do
    expense = create(:category, business: business)
    [ { category: expense }, { transfer: true }, { excluded: true } ].each do |attrs|
      expect(deposit.reload.update(attrs)).to be(false), "accepted #{attrs.keys.first}"
      expect(deposit.errors[:base]).to include(message)
    end
  end

  it "can move to another income category" do
    other_income = create(:category, :income, business: business, name: "Other income", schedule_c_line: "6")
    expect(deposit.update(category: other_income)).to be(true)
  end

  it "can't drop below the amount already allocated" do
    expect(deposit.update(amount_cents: 119_999)).to be(false)
    expect(deposit.errors[:base]).to include(message)
  end

  it "can't be destroyed" do
    expect(deposit.destroy).to be(false)
    expect(Transaction.exists?(deposit.id)).to be(true)
  end

  it "re-dates the paid invoice when its date changes" do
    payment.invoice.sync_payment_status!
    deposit.update!(posted_on: Date.new(2026, 4, 2))
    expect(payment.invoice.reload.paid_on).to eq(Date.new(2026, 4, 2))
  end

  it "reports allocated and unallocated cents" do
    expect(deposit.allocated_cents).to eq(120_000)
    expect(deposit.unallocated_cents).to eq(0)
  end
end

RSpec.describe Transaction, ".linkable_deposits" do
  let(:account) { create(:account) }
  let(:business) { account.business }
  let(:income) { create(:category, :income, business: business) }

  it "keeps positive, countable, uncategorized-or-income deposits with money left to allocate" do
    uncategorized = create(:transaction, account: account, amount_cents: 5_000)
    income_deposit = create(:transaction, account: account, amount_cents: 5_000, category: income)
    create(:transaction, account: account, amount_cents: -5_000)
    create(:transaction, account: account, amount_cents: 5_000, transfer: true)
    create(:transaction, account: account, amount_cents: 5_000, excluded: true)
    create(:transaction, account: account, amount_cents: 5_000, category: create(:category, business: business))
    invoice = create(:invoice, business: business, amount_cents: 5_000)
    full = create(:invoice_payment, invoice: invoice, amount_cents: 5_000).deposit
    partial = create(:invoice_payment, invoice: create(:invoice, business: business, amount_cents: 9_000), amount_cents: 3_000).deposit

    expect(Transaction.linkable_deposits).to contain_exactly(uncategorized, income_deposit, partial)
    expect(Transaction.linkable_deposits.with_unallocated(6_000)).to eq([ partial ])
    expect(full.unallocated_cents).to eq(0)
  end
end
```

Note: in the `partial` line the factory deposit amount is the invoice amount (9_000) and only 3_000 is allocated, so 6_000 remains.

```ruby
# spec/requests/linked_deposit_guards_spec.rb
require "rails_helper"

RSpec.describe "Linked deposit guards" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business) }
  let!(:income) { create(:category, :income, business: business) }
  let!(:invoice) { create(:invoice, business: business, number: "INV-7") }
  let!(:deposit) { create(:transaction, account: account, amount_cents: invoice.amount_cents, category: income, categorized_by: "user") }

  before do
    create(:invoice_payment, invoice: invoice, deposit: deposit)
    sign_in_as user_with_role("editor", business)
  end

  it "refuses to delete a linked manual deposit" do
    delete business_transaction_path(business, deposit)
    expect(response).to redirect_to(edit_business_transaction_path(business, deposit))
    expect(flash[:alert]).to eq("Linked to INV-7 — unlink the payment first.")
    expect(Transaction.exists?(deposit.id)).to be(true)
  end

  it "refuses crafted classification changes" do
    %w[transfer exclude].each do |outcome|
      patch business_transaction_classification_path(business, deposit), params: { outcome: outcome }
      expect(flash[:alert]).to eq("Linked to INV-7 — unlink the payment first.")
    end
    expect(deposit.reload.category).to eq(income)
    expect(deposit).not_to be_transfer
    expect(deposit).not_to be_excluded
  end

  it "re-renders the edit form when recategorized to an expense" do
    patch business_transaction_path(business, deposit), params: { transaction: { category_id: create(:category, business: business).id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Linked to INV-7 — unlink the payment first.")
  end
end
```

Add to `spec/services/rule_applier_spec.rb` inside its top-level `describe`:

```ruby
  it "never touches a deposit linked to an invoice" do
    payment = create(:invoice_payment)
    deposit = payment.deposit
    create(:rule, business: deposit.business, value: "client", outcome: "transfer", category: nil)
    expect(RuleApplier.new(deposit.business).apply([ deposit ])).to eq(0)
    expect(deposit.reload).not_to be_transfer
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/transaction_linked_deposit_spec.rb spec/requests/linked_deposit_guards_spec.rb spec/services/rule_applier_spec.rb`
Expected: FAIL — `update` returns true for transfer/expense, `linkable_deposits` undefined, delete raises `ActiveRecord::RecordNotDestroyed`, classification raises `RecordInvalid` or succeeds.

- [ ] **Step 3: Implement the guards and scopes**

In `app/models/transaction.rb`:

```ruby
  UNALLOCATED_SQL = "transactions.amount_cents - COALESCE((SELECT SUM(invoice_payments.amount_cents) " \
                    "FROM invoice_payments WHERE invoice_payments.deposit_id = transactions.id), 0)".freeze
```

(put it under `CATEGORIZED_BY`), and add after the existing scopes:

```ruby
  scope :linkable_deposits, -> {
    countable.where("transactions.amount_cents > 0")
      .where("transactions.category_id IS NULL OR transactions.category_id IN (SELECT id FROM categories WHERE kind = 'income')")
      .where("#{UNALLOCATED_SQL} > 0")
  }
  scope :with_unallocated, ->(cents) { where("#{UNALLOCATED_SQL} = ?", cents) }
```

after the existing validations:

```ruby
  validate :linked_deposit_stays_payable, on: :update
  after_update :resync_linked_invoices, if: :saved_change_to_posted_on?
```

public methods (after `rule_attributes`):

```ruby
  def allocated_cents = invoice_payments.loaded? ? invoice_payments.sum(&:amount_cents) : invoice_payments.sum(:amount_cents)
  def unallocated_cents = amount_cents - allocated_cents

  def linked_invoice_message
    numbers = invoice_payments.includes(:invoice).map { _1.invoice.number }
    "Linked to #{numbers.join(", ")} — unlink the payment first."
  end
```

private methods:

```ruby
  def linked_deposit_stays_payable
    changed = will_save_change_to_category_id? || will_save_change_to_transfer? ||
              will_save_change_to_excluded? || will_save_change_to_amount_cents?
    return unless changed && invoice_payments.exists?

    payable = !transfer? && !excluded? && category&.income? && amount_cents.to_i >= allocated_cents
    errors.add(:base, linked_invoice_message) unless payable
  end

  def resync_linked_invoices
    invoice_payments.includes(:invoice).each { _1.invoice.sync_payment_status! }
  end
```

- [ ] **Step 4: Handle refusals in the controllers**

`app/controllers/transactions_controller.rb`, replace `destroy`:

```ruby
  def destroy
    if !@transaction.account.manual?
      redirect_to business_transactions_path(@business), alert: "Imported transactions can be excluded, not deleted.", status: :see_other
    elsif @transaction.destroy
      redirect_to business_transactions_path(@business), notice: "Transaction deleted.", status: :see_other
    else
      redirect_to edit_business_transaction_path(@business, @transaction), alert: @transaction.linked_invoice_message, status: :see_other
    end
  end
```

`app/controllers/classifications_controller.rb`, replace `@transaction.update!(attrs.merge(categorized_by: "user"))` with:

```ruby
    unless @transaction.update(attrs.merge(categorized_by: "user"))
      return redirect_back_or_to business_inbox_path(@business), alert: @transaction.errors.full_messages.to_sentence
    end
```

(The transaction edit form already renders `shared/errors`, so `update` re-rendering `:edit` shows the base error.)

- [ ] **Step 5: Run the specs, then the full suite**

Run: `bundle exec rspec spec/models/transaction_linked_deposit_spec.rb spec/requests/linked_deposit_guards_spec.rb spec/services/rule_applier_spec.rb`
Expected: all pass.
Run: `bundle exec rspec && bin/rubocop`
Expected: 0 failures, clean, no offenses.

- [ ] **Step 6: Commit**

```bash
git add app/models/transaction.rb app/controllers/transactions_controller.rb app/controllers/classifications_controller.rb spec/models/transaction_linked_deposit_spec.rb spec/requests/linked_deposit_guards_spec.rb spec/services/rule_applier_spec.rb
git commit -m "Invoices: guard deposits linked to invoices"
```

---

### Task 6: The `InvoicePayments` service

**Files:**
- Create: `app/services/invoice_payments.rb`
- Test: `spec/services/invoice_payments_spec.rb`

**Interfaces:**
- Consumes: `Invoices::Allocation.call` (Task 2), `Invoice#sync_payment_status!`, `#paid_cents`, `Transaction#allocated_cents` (Tasks 4–5).
- Produces: `InvoicePayments.link(invoice:, deposit:, amount_cents: nil, category: nil) → InvoicePayments::Result` and `InvoicePayments.unlink(payment) → InvoicePayments::Result`; `Result` has `#payment`, `#error`, `#ok?`.
- Produces: `InvoicePayments.gross_receipts_categories(business) → [Category]` (active income categories with `schedule_c_line == "1"`, ordered by name) — used by Tasks 10–11.

Category rule for an uncategorized deposit: use `category` if it is an active income category of the business; otherwise, if `category` is nil and the business has exactly one gross-receipts category, use it; otherwise fail with "Choose an income category for this deposit." A deposit that already has an income category keeps it.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/invoice_payments_spec.rb
require "rails_helper"

RSpec.describe InvoicePayments do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }
  let!(:sales) { create(:category, :income, business: business, name: "Sales") }
  let(:invoice) { create(:invoice, business: business, amount_cents: 120_000) }
  let(:deposit) { create(:transaction, account: account, amount_cents: 120_000, posted_on: Date.new(2026, 2, 3), payee: "ACME") }

  describe ".link" do
    it "pays an exact match, categorizes the deposit as Sales by the user, and marks the invoice paid" do
      result = described_class.link(invoice: invoice, deposit: deposit)
      expect(result).to be_ok
      expect(result.payment.amount_cents).to eq(120_000)
      expect(deposit.reload.category).to eq(sales)
      expect(deposit.categorized_by).to eq("user")
      expect(invoice.reload).to be_paid
      expect(invoice.paid_on).to eq(Date.new(2026, 2, 3))
    end

    it "records a partial payment and leaves the invoice sent" do
      result = described_class.link(invoice: invoice, deposit: deposit, amount_cents: 20_000)
      expect(result.payment.amount_cents).to eq(20_000)
      expect(invoice.reload).to be_sent
      expect(invoice.outstanding_cents).to eq(100_000)
    end

    it "keeps an existing income category" do
      other = create(:category, :income, business: business, name: "Other income", schedule_c_line: "6")
      deposit.update!(category: other)
      described_class.link(invoice: invoice, deposit: deposit)
      expect(deposit.reload.category).to eq(other)
    end

    it "asks for a category when the business has several gross-receipts categories" do
      create(:category, :income, business: business, name: "Retail sales")
      result = described_class.link(invoice: invoice, deposit: deposit)
      expect(result.error).to eq("Choose an income category for this deposit.")
      chosen = described_class.link(invoice: invoice, deposit: deposit, category: sales)
      expect(chosen).to be_ok
    end

    it "ignores a category from another business" do
      result = described_class.link(invoice: invoice, deposit: deposit, category: create(:category, :income))
      expect(result.error).to eq("Choose an income category for this deposit.")
    end

    {
      "a draft invoice" => [ -> { invoice.update!(status: "draft") }, "Only sent invoices can take payments." ],
      "a void invoice" => [ -> { invoice.update!(status: "void") }, "Only sent invoices can take payments." ],
      "a paid invoice" => [ -> { invoice.update!(status: "paid") }, "This invoice is already fully paid." ],
      "money out" => [ -> { deposit.update!(amount_cents: -120_000) }, "Only deposits (money in) can pay an invoice." ],
      "a transfer" => [ -> { deposit.update!(transfer: true) }, "Transfers can't pay an invoice." ],
      "an excluded row" => [ -> { deposit.update!(excluded: true) }, "Excluded transactions can't pay an invoice." ],
      "an expense" => [ -> { deposit.update!(category: create(:category, business: business)) }, "Only deposits in an income category can pay an invoice." ]
    }.each do |label, (setup, message)|
      it "rejects #{label}" do
        instance_exec(&setup)
        result = described_class.link(invoice: invoice, deposit: deposit)
        expect(result.error).to eq(message)
        expect(InvoicePayment.count).to eq(0)
      end
    end

    it "rejects a deposit from another business" do
      foreign = create(:transaction, amount_cents: 120_000)
      expect(described_class.link(invoice: invoice, deposit: foreign).error).to eq("That deposit belongs to another business.")
    end

    it "rejects linking the same deposit twice (double submit)" do
      described_class.link(invoice: invoice, deposit: deposit, amount_cents: 10_000)
      expect(described_class.link(invoice: invoice, deposit: deposit).error).to eq("That deposit is already linked to this invoice.")
    end

    it "rejects over-allocation and reports allocation errors" do
      result = described_class.link(invoice: invoice, deposit: deposit, amount_cents: 120_001)
      expect(result.error).to eq("Amount can't exceed the invoice's outstanding $1,200.00.")
    end

    it "re-reads allocations under the lock (stale deposit from an earlier page load)" do
      stale = Transaction.find(deposit.id)
      stale.invoice_payments.load
      other = create(:invoice, business: business, amount_cents: 120_000)
      described_class.link(invoice: other, deposit: Transaction.find(deposit.id))

      expect(invoice).to receive(:lock!).and_call_original
      result = described_class.link(invoice: invoice, deposit: stale)
      expect(result.error).to eq("This deposit is already fully allocated.")
      expect(InvoicePayment.where(deposit_id: deposit.id).sum(:amount_cents)).to eq(120_000)
    end
  end

  describe ".unlink" do
    it "removes the payment and reverts a paid invoice to sent, keeping the deposit's category" do
      payment = described_class.link(invoice: invoice, deposit: deposit).payment
      result = described_class.unlink(payment)
      expect(result).to be_ok
      expect(InvoicePayment.exists?(payment.id)).to be(false)
      expect(invoice.reload).to be_sent
      expect(invoice.paid_on).to be_nil
      expect(deposit.reload.category).to eq(sales)
    end
  end

  it "lists gross-receipts categories" do
    create(:category, :income, business: business, name: "Archived", archived_at: Time.current)
    create(:category, :income, business: business, name: "Other income", schedule_c_line: "6")
    expect(described_class.gross_receipts_categories(business)).to eq([ sales ])
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/services/invoice_payments_spec.rb`
Expected: FAIL with `uninitialized constant InvoicePayments`.

- [ ] **Step 3: Implement**

```ruby
# app/services/invoice_payments.rb
# The only writer of InvoicePayment rows. Locks (and so re-reads) the invoice and the deposit,
# then lets Invoice#sync_payment_status! decide paid vs. sent.
class InvoicePayments
  Result = Data.define(:payment, :error) do
    def ok? = error.nil?
  end

  def self.gross_receipts_categories(business)
    business.categories.active.income.where(schedule_c_line: "1").order(:name).to_a
  end

  def self.link(invoice:, deposit:, amount_cents: nil, category: nil)
    ApplicationRecord.transaction do
      invoice.lock!
      deposit.lock!
      error = link_error(invoice, deposit)
      next failure(error) if error

      allocation = Invoices::Allocation.call(
        invoice_amount_cents: invoice.amount_cents, invoice_paid_cents: invoice.paid_cents,
        deposit_amount_cents: deposit.amount_cents, deposit_allocated_cents: deposit.allocated_cents,
        requested_cents: amount_cents
      )
      next failure(allocation.error) unless allocation.ok?

      income = income_category_for(deposit, category)
      next failure("Choose an income category for this deposit.") unless income

      deposit.update!(category: income, categorized_by: "user") unless deposit.category_id == income.id
      payment = invoice.payments.create!(deposit: deposit, amount_cents: allocation.amount_cents)
      invoice.sync_payment_status!
      Result.new(payment: payment, error: nil)
    end
  end

  def self.unlink(payment)
    ApplicationRecord.transaction do
      invoice = payment.invoice
      invoice.lock!
      payment.destroy!
      invoice.sync_payment_status!
      Result.new(payment: payment, error: nil)
    end
  end

  def self.link_error(invoice, deposit)
    if invoice.paid? then "This invoice is already fully paid."
    elsif !invoice.sent? then "Only sent invoices can take payments."
    elsif deposit.account.business_id != invoice.business_id then "That deposit belongs to another business."
    elsif !deposit.amount_cents.positive? then "Only deposits (money in) can pay an invoice."
    elsif deposit.transfer? then "Transfers can't pay an invoice."
    elsif deposit.excluded? then "Excluded transactions can't pay an invoice."
    elsif deposit.category && !deposit.category.income? then "Only deposits in an income category can pay an invoice."
    elsif invoice.payments.exists?(deposit_id: deposit.id) then "That deposit is already linked to this invoice."
    end
  end

  def self.income_category_for(deposit, requested)
    return deposit.category if deposit.category
    return requested if requested && deposit.business.categories.active.income.exists?(requested.id)
    return nil if requested

    candidates = gross_receipts_categories(deposit.business)
    candidates.first if candidates.one?
  end

  def self.failure(message) = Result.new(payment: nil, error: message)

  private_class_method :link_error, :income_category_for, :failure
end
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec rspec spec/services/invoice_payments_spec.rb && bin/rubocop app/services/invoice_payments.rb spec/services/invoice_payments_spec.rb`
Expected: all pass, no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/services/invoice_payments.rb spec/services/invoice_payments_spec.rb
git commit -m "Invoices: InvoicePayments link/unlink service"
```

---
### Task 7: Clients screens

**Files:**
- Create: `app/controllers/clients_controller.rb`
- Create: `app/views/clients/index.html.erb`, `new.html.erb`, `edit.html.erb`, `_form.html.erb`
- Modify: `config/routes.rb`, `app/views/businesses/_nav.html.erb`
- Test: `spec/requests/clients_spec.rb`

**Interfaces:**
- Consumes: `Client` (Task 4), `BusinessScoped` (`@business`, `require_editor!`, `current_membership`).
- Produces: routes `business_clients_path`, `new_business_client_path`, `edit_business_client_path`.

- [ ] **Step 1: Write the failing request spec**

```ruby
# spec/requests/clients_spec.rb
require "rails_helper"

RSpec.describe "Clients" do
  let!(:business) { create(:business) }
  let!(:client) { create(:client, business: business, name: "Acme") }

  it "lists active clients to viewers and hides archived ones until asked" do
    create(:client, business: business, name: "Old Co", archived_at: Time.current)
    sign_in_as user_with_role("viewer", business)
    get business_clients_path(business)
    expect(response.body).to include("Acme")
    expect(response.body).not_to include("Old Co")
    get business_clients_path(business, archived: "1")
    expect(response.body).to include("Old Co")
  end

  it "404s for non-members" do
    sign_in_as create(:user)
    get business_clients_path(business)
    expect(response).to have_http_status(:not_found)
  end

  it "forbids viewers from writing" do
    sign_in_as user_with_role("viewer", business)
    get new_business_client_path(business)
    expect(response).to have_http_status(:forbidden)
    post business_clients_path(business), params: { client: { name: "New" } }
    expect(response).to have_http_status(:forbidden)
    patch business_client_path(business, client), params: { client: { name: "Renamed" } }
    expect(response).to have_http_status(:forbidden)
    expect(client.reload.name).to eq("Acme")
  end

  it "lets editors add, rename, and archive clients" do
    sign_in_as user_with_role("editor", business)
    post business_clients_path(business), params: { client: { name: "Globex", email: "ap@globex.test", notes: "Net 30" } }
    expect(response).to redirect_to(business_clients_path(business))
    expect(business.clients.find_by!(name: "Globex").email).to eq("ap@globex.test")

    patch business_client_path(business, client), params: { client: { name: "Acme Corp", archived: "1" } }
    expect(client.reload.name).to eq("Acme Corp")
    expect(client).to be_archived
    patch business_client_path(business, client), params: { client: { archived: "0" } }
    expect(client.reload).not_to be_archived
  end

  it "re-renders invalid input" do
    sign_in_as user_with_role("editor", business)
    post business_clients_path(business), params: { client: { name: "Acme" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "404s for another business's client" do
    other = create(:client)
    sign_in_as user_with_role("owner", business)
    get edit_business_client_path(business, other)
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/requests/clients_spec.rb`
Expected: FAIL with `undefined method 'business_clients_path'`.

- [ ] **Step 3: Routes, controller, views, nav**

In `config/routes.rb`, inside `resources :businesses ... do`, after `resources :categories, ...`:

```ruby
    resources :clients, only: %i[index new create edit update]
```

```ruby
# app/controllers/clients_controller.rb
class ClientsController < ApplicationController
  include BusinessScoped

  PERMITTED = %i[name email notes].freeze

  before_action :require_editor!, except: :index
  before_action :set_client, only: %i[edit update]

  def index
    @show_archived = params[:archived] == "1"
    @clients = @business.clients.order(:archived_at, :name)
    @clients = @clients.active unless @show_archived
  end

  def new
    @client = @business.clients.new
  end

  def create
    @client = @business.clients.new(params.expect(client: PERMITTED))
    if @client.save
      redirect_to business_clients_path(@business), notice: "Client added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    attrs = params.expect(client: [ *PERMITTED, :archived ])
    archived = attrs.delete(:archived)
    @client.assign_attributes(attrs)
    @client.archived_at = archived == "1" ? (@client.archived_at || Time.current) : nil unless archived.nil?
    if @client.save
      redirect_to business_clients_path(@business), notice: "Client updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_client
    @client = @business.clients.find(params[:id])
  end
end
```

```erb
<%# app/views/clients/index.html.erb %>
<%= business_nav @business %>
<h1>Clients</h1>
<% if @show_archived %>
  <%= link_to "Hide archived", business_clients_path(@business) %>
<% else %>
  <%= link_to "Show archived", business_clients_path(@business, archived: "1") %>
<% end %>
<table>
  <thead><tr><th>Name</th><th>Email</th><th>Notes</th><th></th></tr></thead>
  <tbody>
    <% @clients.each do |client| %>
      <tr id="<%= dom_id(client) %>">
        <td><%= client.name %><%= " (archived)" if client.archived? %></td>
        <td><%= client.email %></td>
        <td><%= truncate(client.notes, length: 80) %></td>
        <td><%= link_to "Edit", edit_business_client_path(@business, client) if current_membership.can_edit? %></td>
      </tr>
    <% end %>
  </tbody>
</table>
<%= link_to "New client", new_business_client_path(@business) if current_membership.can_edit? %>
```

```erb
<%# app/views/clients/_form.html.erb %>
<%= form_with model: [@business, client] do |f| %>
  <%= render "shared/errors", record: client %>
  <p><%= f.label :name %> <%= f.text_field :name, required: true %></p>
  <p><%= f.label :email %> <%= f.email_field :email %></p>
  <p><%= f.label :notes %> <%= f.text_area :notes, rows: 3 %></p>
  <% if client.persisted? %>
    <p><%= f.label :archived %> <%= f.check_box :archived, { checked: client.archived? }, "1", "0" %></p>
  <% end %>
  <%= f.submit %>
<% end %>
```

```erb
<%# app/views/clients/new.html.erb %>
<%= business_nav @business %>
<h1>New client</h1>
<%= render "form", client: @client %>
```

```erb
<%# app/views/clients/edit.html.erb %>
<%= business_nav @business %>
<h1>Edit client</h1>
<%= render "form", client: @client %>
```

In `app/views/businesses/_nav.html.erb`, after the Mileage item:

```erb
    <li><%= link_to "Clients", business_clients_path(business) %></li>
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec rspec spec/requests/clients_spec.rb && bin/rubocop`
Expected: pass, no offenses.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/clients_controller.rb app/views/clients app/views/businesses/_nav.html.erb spec/requests/clients_spec.rb
git commit -m "Invoices: clients screens"
```

---

### Task 8: Invoice list, form, page, and status actions

**Files:**
- Create: `app/models/invoice_filter.rb`
- Create: `app/controllers/invoices_controller.rb`, `app/helpers/invoices_helper.rb`
- Create: `app/views/invoices/index.html.erb`, `_table.html.erb`, `_form.html.erb`, `new.html.erb`, `edit.html.erb`, `show.html.erb`, `_payments.html.erb`, `_actions.html.erb`
- Modify: `config/routes.rb`, `app/views/businesses/_nav.html.erb`, `app/assets/stylesheets/application.css`
- Test: `spec/models/invoice_filter_spec.rb`, `spec/requests/invoices_spec.rb`

**Interfaces:**
- Consumes: `Invoice` (Task 4), `Invoices::NumberSuggester.next` (Task 2), `ScalarParams#scalar_params` (Task 1).
- Produces: `InvoiceFilter.new(scope, params, today: Date.current)` with `#results` (page of 50, preloads client/business/payments), `#all`, `#next_page?`, `#params`, `#page`, `#outstanding_cents`, `#overdue_cents`; `InvoiceFilter::STATUSES` (`{"open"=>"Open", "overdue"=>"Overdue", "paid"=>"Paid", "draft"=>"Draft", "void"=>"Void"}`).
- Produces: `InvoicesHelper#invoice_status_badge(invoice)`, `#invoice_outstanding(invoice)`, `#invoice_status_filter_options`, `#invoice_client_options(business, invoice)`.
- Produces: partial `invoices/_table` (locals `invoices:`, `show_business:`), reused by the household list in Task 12; partials `invoices/_payments` and `invoices/_actions` (local `invoice:`), extended in Tasks 9–10.
- Produces routes: `business_invoices_path`, `business_invoice_path`, `new_/edit_business_invoice_path`, `mark_sent_/void_/reopen_business_invoice_path`.

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/models/invoice_filter_spec.rb
require "rails_helper"

RSpec.describe InvoiceFilter do
  let(:business) { create(:business) }
  let(:today) { Date.new(2026, 10, 6) }
  let(:acme) { create(:client, business: business, name: "Acme") }
  let!(:current) { create(:invoice, business: business, client: acme, number: "C", issue_date: today - 5, due_date: today, amount_cents: 10_000) }
  let!(:late) { create(:invoice, business: business, number: "L", issue_date: today - 40, due_date: today - 10, amount_cents: 20_000) }
  let!(:paid) { create(:invoice, business: business, number: "P", status: "paid", issue_date: today - 60, due_date: today - 30) }
  let!(:draft) { create(:invoice, business: business, number: "D", status: "draft", issue_date: today - 1, due_date: today + 29) }

  def numbers(params) = described_class.new(business.invoices, params, today: today).results.map(&:number)

  it "filters by status" do
    expect(numbers({})).to eq(%w[D C L P])
    expect(numbers(status: "open")).to contain_exactly("C", "L")
    expect(numbers(status: "overdue")).to eq(%w[L])
    expect(numbers(status: "paid")).to eq(%w[P])
    expect(numbers(status: "draft")).to eq(%w[D])
    expect(numbers(status: "nonsense")).to eq(%w[D C L P])
  end

  it "filters by client and issue date" do
    expect(numbers(client_id: acme.id.to_s)).to eq(%w[C])
    expect(numbers(from: (today - 45).iso8601, to: (today - 2).iso8601)).to eq(%w[C L])
  end

  it "totals outstanding and overdue over sent invoices" do
    filter = described_class.new(business.invoices, {}, today: today)
    expect(filter.outstanding_cents).to eq(30_000)
    expect(filter.overdue_cents).to eq(20_000)
  end
end
```

```ruby
# spec/requests/invoices_spec.rb
require "rails_helper"

RSpec.describe "Invoices" do
  let!(:business) { create(:business) }
  let!(:client) { create(:client, business: business, name: "Acme") }
  let!(:invoice) { create(:invoice, business: business, client: client, number: "INV-0042", amount_cents: 120_000) }
  let(:valid) { { client_id: client.id.to_s, number: "INV-0043", issue_date: "2026-10-01", due_date: "2026-10-31", amount: "$1,500.00" } }

  describe "reading" do
    it "lists and shows invoices to viewers" do
      sign_in_as user_with_role("viewer", business)
      get business_invoices_path(business)
      expect(response.body).to include("INV-0042", "Acme", "$1,200.00")
      get business_invoice_path(business, invoice)
      expect(response).to have_http_status(:ok)
    end

    it "404s for non-members and for another business's invoice" do
      sign_in_as create(:user)
      get business_invoices_path(business)
      expect(response).to have_http_status(:not_found)

      sign_in_as user_with_role("owner", business)
      get business_invoice_path(business, create(:invoice))
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "writing" do
    it "forbids viewers from every write" do
      sign_in_as user_with_role("viewer", business)
      get new_business_invoice_path(business)
      expect(response).to have_http_status(:forbidden)
      post business_invoices_path(business), params: { invoice: valid }
      expect(response).to have_http_status(:forbidden)
      patch business_invoice_path(business, invoice), params: { invoice: { number: "X" } }
      expect(response).to have_http_status(:forbidden)
      %i[mark_sent void reopen].each do |action|
        patch send("#{action}_business_invoice_path", business, invoice)
        expect(response).to have_http_status(:forbidden)
      end
      delete business_invoice_path(business, invoice)
      expect(response).to have_http_status(:forbidden)
      expect(invoice.reload).to be_sent
    end

    it "prefills the next number and dates" do
      sign_in_as user_with_role("editor", business)
      get new_business_invoice_path(business)
      expect(response.body).to include('value="INV-0043"')
    end

    it "creates a sent invoice by default, or a draft" do
      sign_in_as user_with_role("editor", business)
      post business_invoices_path(business), params: { invoice: valid }
      created = business.invoices.find_by!(number: "INV-0043")
      expect(response).to redirect_to(business_invoice_path(business, created))
      expect(created).to be_sent
      expect(created.amount_cents).to eq(150_000)

      post business_invoices_path(business), params: { invoice: valid.merge(number: "INV-0044", status: "draft") }
      expect(business.invoices.find_by!(number: "INV-0044")).to be_draft
    end

    it "never takes a paid status from the form" do
      sign_in_as user_with_role("editor", business)
      post business_invoices_path(business), params: { invoice: valid.merge(status: "paid") }
      expect(business.invoices.find_by!(number: "INV-0043")).to be_sent
    end

    it "creates a new client inline" do
      sign_in_as user_with_role("editor", business)
      post business_invoices_path(business), params: { invoice: valid.merge(client_id: "new", new_client_name: "Globex") }
      expect(business.invoices.find_by!(number: "INV-0043").client.name).to eq("Globex")
    end

    it "keeps no orphan client when the invoice is invalid" do
      sign_in_as user_with_role("editor", business)
      expect {
        post business_invoices_path(business), params: { invoice: valid.merge(client_id: "new", new_client_name: "Globex", amount: "abc") }
      }.not_to change(Client, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s for a client from another business" do
      sign_in_as user_with_role("editor", business)
      post business_invoices_path(business), params: { invoice: valid.merge(client_id: create(:client).id.to_s) }
      expect(response).to have_http_status(:not_found)
    end

    it "re-renders typed amounts that don't parse" do
      sign_in_as user_with_role("editor", business)
      %w[abc 0 -5].each do |amount|
        post business_invoices_path(business), params: { invoice: valid.merge(amount: amount) }
        expect(response).to have_http_status(:unprocessable_content), "accepted #{amount}"
      end
    end

    it "updates an invoice" do
      sign_in_as user_with_role("editor", business)
      patch business_invoice_path(business, invoice), params: { invoice: { description: "October retainer" } }
      expect(response).to redirect_to(business_invoice_path(business, invoice))
      expect(invoice.reload.description).to eq("October retainer")
    end

    it "reverts a paid invoice to sent when its amount is raised" do
      create(:invoice_payment, invoice: invoice)
      invoice.sync_payment_status!
      sign_in_as user_with_role("editor", business)
      patch business_invoice_path(business, invoice), params: { invoice: { amount: "1,500.00" } }
      expect(invoice.reload).to be_sent
      expect(invoice.outstanding_cents).to eq(30_000)
    end

    it "marks drafts sent, voids, and reopens" do
      draft = create(:invoice, business: business, status: "draft")
      sign_in_as user_with_role("editor", business)
      patch mark_sent_business_invoice_path(business, draft)
      expect(draft.reload).to be_sent
      patch void_business_invoice_path(business, draft)
      expect(draft.reload).to be_void
      patch reopen_business_invoice_path(business, draft)
      expect(draft.reload).to be_sent
      patch mark_sent_business_invoice_path(business, draft)
      expect(flash[:alert]).to eq("This invoice can't be marked sent while it is sent.")
    end

    it "deletes an invoice without payments, and refuses one with payments" do
      sign_in_as user_with_role("editor", business)
      linked = create(:invoice_payment, invoice: create(:invoice, business: business)).invoice
      delete business_invoice_path(business, linked)
      expect(flash[:alert]).to eq("Unlink its payments before deleting this invoice.")
      expect(Invoice.exists?(linked.id)).to be(true)

      delete business_invoice_path(business, invoice)
      expect(response).to redirect_to(business_invoices_path(business))
      expect(Invoice.exists?(invoice.id)).to be(false)
    end
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/invoice_filter_spec.rb spec/requests/invoices_spec.rb`
Expected: FAIL with `uninitialized constant InvoiceFilter` / `undefined method 'business_invoices_path'`.

- [ ] **Step 3: Filter**

```ruby
# app/models/invoice_filter.rb
class InvoiceFilter
  PER_PAGE = 50
  STATUSES = { "open" => "Open", "overdue" => "Overdue", "paid" => "Paid", "draft" => "Draft", "void" => "Void" }.freeze

  attr_reader :page

  def initialize(scope, params, today: Date.current)
    @scope = scope
    @params = params.to_h.symbolize_keys
    @today = today
    @page = [ [ @params[:page].to_i, 1 ].max, 10_000 ].min
  end

  def results = ordered.limit(PER_PAGE).offset((page - 1) * PER_PAGE)
  def all = ordered
  def next_page? = filtered.count > page * PER_PAGE
  def params = @params.slice(:status, :client_id, :from, :to)
  def outstanding_cents = open_invoices.sum(&:outstanding_cents)
  def overdue_cents = open_invoices.select { _1.overdue?(@today) }.sum(&:outstanding_cents)

  private

  def ordered = filtered.includes(:client, :business, :payments).order(issue_date: :desc, id: :desc)

  def open_invoices
    @open_invoices ||= filtered.sent.includes(:payments).to_a
  end

  def filtered
    relation =
      case @params[:status]
      when "open" then @scope.sent
      when "overdue" then @scope.sent.where("invoices.due_date < ?", @today)
      when "paid", "draft", "void" then @scope.where(status: @params[:status])
      else @scope
      end
    relation = relation.where(client_id: @params[:client_id]) if @params[:client_id].present?
    relation = relation.where(issue_date: date(:from)..) if date(:from)
    relation = relation.where(issue_date: ..date(:to)) if date(:to)
    relation
  end

  def date(key)
    Date.iso8601(@params[key].to_s)
  rescue Date::Error
    nil
  end
end
```

- [ ] **Step 4: Routes, controller, helper**

In `config/routes.rb`, after the `resources :clients` line:

```ruby
    resources :invoices do
      member do
        patch :mark_sent
        patch :void
        patch :reopen
      end
    end
```

```ruby
# app/controllers/invoices_controller.rb
class InvoicesController < ApplicationController
  include BusinessScoped
  include ScalarParams

  PERMITTED = %i[number issue_date due_date amount description].freeze

  before_action :require_editor!, except: %i[index show]
  before_action :set_invoice, only: %i[show edit update destroy mark_sent void reopen]

  def index
    @filter = InvoiceFilter.new(@business.invoices, scalar_params(:status, :client_id, :from, :to, :page))
    @invoices = @filter.results
  end

  def show
    @payments = @invoice.payments.includes(deposit: :account).order(:created_at)
  end

  def new
    today = Date.current
    @invoice = @business.invoices.new(number: Invoices::NumberSuggester.next(@business.invoices.pluck(:number)),
                                      issue_date: today, due_date: today + 30, status: "sent")
  end

  def create
    @invoice = @business.invoices.new(params.expect(invoice: PERMITTED))
    @invoice.status = params.dig(:invoice, :status) == "draft" ? "draft" : "sent"
    assign_client
    if save_with_client
      redirect_to business_invoice_path(@business, @invoice), notice: "Invoice added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @invoice.assign_attributes(params.expect(invoice: PERMITTED))
    assign_client
    if save_with_client
      @invoice.sync_payment_status!
      redirect_to business_invoice_path(@business, @invoice), notice: "Invoice updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @invoice.destroy
      redirect_to business_invoices_path(@business), notice: "Invoice deleted.", status: :see_other
    else
      redirect_to business_invoice_path(@business, @invoice), alert: "Unlink its payments before deleting this invoice.", status: :see_other
    end
  end

  def mark_sent = transition("mark_sent", "Invoice marked sent.")
  def void = transition("void", "Invoice voided.")
  def reopen = transition("reopen", "Invoice reopened.")

  private

  def set_invoice
    @invoice = @business.invoices.find(params[:id])
  end

  def transition(event, notice)
    if @invoice.apply_event(event)
      redirect_to business_invoice_path(@business, @invoice), notice: notice, status: :see_other
    else
      redirect_to business_invoice_path(@business, @invoice), alert: @invoice.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # client_id is resolved through the business, never mass-assigned. "new" creates a client from new_client_name.
  def assign_client
    choice = params.dig(:invoice, :client_id)
    return unless choice.is_a?(String) && choice.present?

    if choice == "new"
      @invoice.client = @business.clients.new(name: params.dig(:invoice, :new_client_name).to_s.strip)
    else
      selectable = @business.clients.where(archived_at: nil).or(@business.clients.where(id: @invoice.client_id_was))
      @invoice.client = selectable.find(choice)
    end
  end

  def save_with_client
    ApplicationRecord.transaction do
      client = @invoice.client
      if client&.new_record? && !client.save
        @invoice.validate
        @invoice.errors.add(:client, client.errors.full_messages.to_sentence)
        raise ActiveRecord::Rollback
      end
      @invoice.save || raise(ActiveRecord::Rollback)
    end
  end
end
```

```ruby
# app/helpers/invoices_helper.rb
module InvoicesHelper
  def invoice_status_badge(invoice)
    status = invoice.display_status
    tag.span(status.humanize, class: "badge badge-#{status}")
  end

  def invoice_outstanding(invoice)
    invoice.sent? || invoice.paid? ? money(invoice.outstanding_cents) : "—"
  end

  def invoice_status_filter_options
    [ [ "All statuses", "" ] ] + InvoiceFilter::STATUSES.map { |value, label| [ label, value ] }
  end

  def invoice_client_options(business, invoice)
    clients = business.clients.where(archived_at: nil).or(business.clients.where(id: invoice.client_id)).order(:name)
    selected = (params.dig(:invoice, :client_id) || invoice.client_id).to_s
    options_for_select(clients.map { [ _1.name, _1.id.to_s ] } + [ [ "New client…", "new" ] ], selected)
  end
end
```

- [ ] **Step 5: Views and styles**

```erb
<%# app/views/invoices/index.html.erb %>
<%= business_nav @business %>
<h1>Invoices</h1>
<p>Outstanding <%= money(@filter.outstanding_cents) %> · Overdue <%= money(@filter.overdue_cents) %></p>
<%= form_with url: business_invoices_path(@business), method: :get, class: "inline-form no-print" do |f| %>
  <%= f.select :status, invoice_status_filter_options, selected: params[:status] %>
  <%= f.select :client_id, options_from_collection_for_select(@business.clients.order(:name), :id, :name, params[:client_id]), include_blank: "All clients" %>
  <%= f.date_field :from, value: params[:from] %>
  <%= f.date_field :to, value: params[:to] %>
  <%= f.submit "Filter" %>
<% end %>
<%= render "invoices/table", invoices: @invoices, show_business: false %>
<p>
  <%= link_to "Previous", business_invoices_path(@business, @filter.params.merge(page: @filter.page - 1)) if @filter.page > 1 %>
  <%= link_to "Next", business_invoices_path(@business, @filter.params.merge(page: @filter.page + 1)) if @filter.next_page? %>
</p>
<%= link_to "New invoice", new_business_invoice_path(@business) if current_membership.can_edit? %>
```

```erb
<%# app/views/invoices/_table.html.erb %>
<table>
  <thead>
    <tr>
      <th>Number</th><% if show_business %><th>Business</th><% end %><th>Client</th><th>Issued</th><th>Due</th>
      <th class="num">Amount</th><th class="num">Paid</th><th class="num">Outstanding</th><th>Status</th>
    </tr>
  </thead>
  <tbody>
    <% invoices.each do |invoice| %>
      <tr id="<%= dom_id(invoice) %>">
        <td><%= link_to invoice.number, business_invoice_path(invoice.business, invoice) %></td>
        <% if show_business %><td><%= invoice.business.name %></td><% end %>
        <td><%= invoice.client.name %></td>
        <td><%= invoice.issue_date %></td>
        <td><%= invoice.due_date %></td>
        <td class="num"><%= money(invoice.amount_cents) %></td>
        <td class="num"><%= money(invoice.paid_cents) %></td>
        <td class="num"><%= invoice_outstanding(invoice) %></td>
        <td><%= invoice_status_badge(invoice) %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

```erb
<%# app/views/invoices/_form.html.erb %>
<%= form_with model: [@business, invoice] do |f| %>
  <%= render "shared/errors", record: invoice %>
  <p>
    <%= f.label :client_id, "Client" %>
    <%= f.select :client_id, invoice_client_options(@business, invoice), { include_blank: "Choose…" }, required: true %>
    <%= text_field_tag "invoice[new_client_name]", params.dig(:invoice, :new_client_name), placeholder: "New client name", aria: { label: "New client name" } %>
  </p>
  <p><%= f.label :number %> <%= f.text_field :number, required: true %></p>
  <p><%= f.label :issue_date %> <%= f.date_field :issue_date, required: true %></p>
  <p><%= f.label :due_date %> <%= f.date_field :due_date, required: true %></p>
  <p><%= f.label :amount %> <%= f.text_field :amount, required: true, inputmode: "decimal" %></p>
  <p><%= f.label :description %> <%= f.text_area :description, rows: 3 %></p>
  <% if invoice.new_record? %>
    <p><%= f.label :status %> <%= f.select :status, [ [ "Sent", "sent" ], [ "Draft (not sent yet)", "draft" ] ] %></p>
  <% end %>
  <%= f.submit %>
<% end %>
```

```erb
<%# app/views/invoices/new.html.erb %>
<%= business_nav @business %>
<h1>New invoice</h1>
<%= render "form", invoice: @invoice %>
```

```erb
<%# app/views/invoices/edit.html.erb %>
<%= business_nav @business %>
<h1>Edit invoice <%= @invoice.number %></h1>
<%= render "form", invoice: @invoice %>
```

```erb
<%# app/views/invoices/show.html.erb %>
<%= business_nav @business %>
<h1>Invoice <%= @invoice.number %> <%= invoice_status_badge(@invoice) %></h1>
<dl class="details">
  <dt>Client</dt><dd><%= @invoice.client.name %></dd>
  <dt>Issued</dt><dd><%= @invoice.issue_date %></dd>
  <dt>Due</dt><dd><%= @invoice.due_date %><%= " (#{pluralize(@invoice.days_past_due, "day")} past due)" if @invoice.overdue? %></dd>
  <dt>Amount</dt><dd><%= money(@invoice.amount_cents) %></dd>
  <dt>Paid</dt><dd><%= money(@invoice.paid_cents) %><%= " on #{@invoice.paid_on}" if @invoice.paid? %></dd>
  <dt>Outstanding</dt><dd><%= invoice_outstanding(@invoice) %></dd>
  <% if @invoice.description.present? %>
    <dt>Description</dt><dd><%= @invoice.description %></dd>
  <% end %>
</dl>
<%= render "invoices/payments", invoice: @invoice, payments: @payments %>
<%= render "invoices/actions", invoice: @invoice %>
```

```erb
<%# app/views/invoices/_payments.html.erb %>
<h2>Payments</h2>
<% if payments.any? %>
  <table>
    <thead><tr><th>Deposit date</th><th>Account</th><th>Payee</th><th class="num">Amount</th></tr></thead>
    <tbody>
      <% payments.each do |payment| %>
        <tr id="<%= dom_id(payment) %>">
          <td><%= payment.deposit.posted_on %></td>
          <td><%= payment.deposit.account.name %></td>
          <td><%= payment.deposit.payee %></td>
          <td class="num"><%= money(payment.amount_cents) %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% else %>
  <p>No payments linked yet.</p>
<% end %>
```

```erb
<%# app/views/invoices/_actions.html.erb %>
<% if current_membership.can_edit? %>
  <p class="actions">
    <%= link_to "Edit", edit_business_invoice_path(@business, invoice) %>
    <%= button_to "Mark sent", mark_sent_business_invoice_path(@business, invoice), method: :patch, form_class: "inline-form" if invoice.draft? %>
    <%= button_to "Void", void_business_invoice_path(@business, invoice), method: :patch, form_class: "inline-form" if (invoice.draft? || invoice.sent?) && invoice.payments.none? %>
    <%= button_to "Reopen", reopen_business_invoice_path(@business, invoice), method: :patch, form_class: "inline-form" if invoice.void? %>
    <%= button_to "Delete", business_invoice_path(@business, invoice), method: :delete, form_class: "inline-form" if invoice.payments.none? %>
  </p>
<% end %>
<%= link_to "All invoices", business_invoices_path(@business) %>
```

In `app/views/businesses/_nav.html.erb`, before the Clients item added in Task 7:

```erb
    <li><%= link_to "Invoices", business_invoices_path(business) %></li>
```

Append to `app/assets/stylesheets/application.css`:

```css
.badge { display: inline-block; padding: 0 .4rem; border: 1px solid var(--line); border-radius: .6rem; font-size: .8rem; font-weight: normal; }
.badge-paid { color: var(--accent); border-color: var(--accent); }
.badge-overdue { color: var(--bad); border-color: var(--bad); }
.badge-draft, .badge-void { color: var(--muted); }
dl.details { display: grid; grid-template-columns: max-content 1fr; gap: .25rem 1rem; }
.actions { display: flex; gap: .5rem; align-items: center; }
```

- [ ] **Step 6: Run the specs, then the full suite**

Run: `bundle exec rspec spec/models/invoice_filter_spec.rb spec/requests/invoices_spec.rb`
Expected: all pass.
Run: `bundle exec rspec && bin/rubocop && bin/brakeman --no-pager -q`
Expected: 0 failures, clean; no offenses; no warnings.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/models/invoice_filter.rb app/controllers/invoices_controller.rb app/helpers/invoices_helper.rb app/views/invoices app/views/businesses/_nav.html.erb app/assets/stylesheets/application.css spec/models/invoice_filter_spec.rb spec/requests/invoices_spec.rb
git commit -m "Invoices: list, form, page, and status actions"
```

---

### Task 9: Invoice PDF attachment

**Files:**
- Modify: `app/models/invoice.rb`, `app/controllers/invoices_controller.rb` (`PERMITTED`), `app/views/invoices/_form.html.erb`, `app/views/invoices/show.html.erb`, `config/routes.rb`
- Create: `app/controllers/invoice_pdfs_controller.rb`
- Create: `spec/fixtures/files/invoice.pdf`
- Test: `spec/requests/invoice_pdfs_spec.rb`, `spec/models/invoice_spec.rb` (add examples)

**Interfaces:**
- Consumes: `Invoice`, `BusinessScoped`.
- Produces: `Invoice#pdf` (`has_one_attached`), `Invoice::PDF_MAX_BYTES`, route `business_invoice_pdf_path(business, invoice)`.

- [ ] **Step 1: Create the fixture PDF**

```bash
printf '%%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Kids [] /Count 0 >> endobj\ntrailer << /Root 1 0 R >>\n%%%%EOF\n' > spec/fixtures/files/invoice.pdf
head -c 8 spec/fixtures/files/invoice.pdf
```

Expected output starts with `%PDF-1.4`.

- [ ] **Step 2: Write the failing specs**

Add to `spec/models/invoice_spec.rb`:

```ruby
  describe "pdf" do
    it "accepts a PDF" do
      invoice = build(:invoice)
      invoice.pdf.attach(io: file_fixture("invoice.pdf").open, filename: "invoice.pdf")
      expect(invoice).to be_valid
    end

    it "rejects other file types" do
      invoice = build(:invoice)
      invoice.pdf.attach(io: file_fixture("checking.csv").open, filename: "checking.csv")
      expect(invoice).not_to be_valid
      expect(invoice.errors[:pdf]).to include("must be a PDF")
    end

    it "rejects files over the size limit" do
      stub_const("Invoice::PDF_MAX_BYTES", 10)
      invoice = build(:invoice)
      invoice.pdf.attach(io: file_fixture("invoice.pdf").open, filename: "invoice.pdf")
      expect(invoice).not_to be_valid
      expect(invoice.errors[:pdf]).to include("must be smaller than 10 MB")
    end
  end
```

```ruby
# spec/requests/invoice_pdfs_spec.rb
require "rails_helper"

RSpec.describe "Invoice PDFs" do
  let!(:business) { create(:business) }
  let!(:invoice) { create(:invoice, business: business) }
  let(:pdf) { fixture_file_upload("invoice.pdf", "application/pdf") }

  it "lets editors upload a PDF and members view it inline" do
    sign_in_as user_with_role("editor", business)
    patch business_invoice_path(business, invoice), params: { invoice: { pdf: pdf } }
    expect(invoice.reload.pdf).to be_attached

    sign_in_as user_with_role("viewer", business)
    get business_invoice_pdf_path(business, invoice)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to start_with("inline")
    expect(response.body).to start_with("%PDF")
  end

  it "404s when there is no PDF, for non-members, and across businesses" do
    sign_in_as user_with_role("viewer", business)
    get business_invoice_pdf_path(business, invoice)
    expect(response).to have_http_status(:not_found)

    other = create(:invoice)
    other.pdf.attach(io: file_fixture("invoice.pdf").open, filename: "invoice.pdf")
    other.save!
    get business_invoice_pdf_path(business, other)
    expect(response).to have_http_status(:not_found)

    sign_in_as create(:user)
    get business_invoice_pdf_path(other.business, other)
    expect(response).to have_http_status(:not_found)
  end

  it "re-renders a non-PDF upload" do
    sign_in_as user_with_role("editor", business)
    patch business_invoice_path(business, invoice), params: { invoice: { pdf: fixture_file_upload("checking.csv", "text/csv") } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(invoice.reload.pdf).not_to be_attached
  end
end
```

- [ ] **Step 3: Run them to see them fail**

Run: `bundle exec rspec spec/models/invoice_spec.rb spec/requests/invoice_pdfs_spec.rb`
Expected: FAIL with `undefined method 'pdf'` / `undefined method 'business_invoice_pdf_path'`.

- [ ] **Step 4: Implement**

In `app/models/invoice.rb`: add `PDF_MAX_BYTES = 10.megabytes` under `EVENTS`, `has_one_attached :pdf` after `has_many :payments`, `validate :pdf_is_a_small_pdf` after the other validates, and the private method:

```ruby
  def pdf_is_a_small_pdf
    return unless pdf.attached?

    errors.add(:pdf, "must be a PDF") unless pdf.blob.content_type == "application/pdf"
    errors.add(:pdf, "must be smaller than 10 MB") if pdf.blob.byte_size > PDF_MAX_BYTES
  end
```

In `app/controllers/invoices_controller.rb`: `PERMITTED = %i[number issue_date due_date amount description pdf].freeze`.

In `config/routes.rb`, change the invoices block to:

```ruby
    resources :invoices do
      member do
        patch :mark_sent
        patch :void
        patch :reopen
      end
      resource :pdf, only: :show, controller: "invoice_pdfs"
    end
```

```ruby
# app/controllers/invoice_pdfs_controller.rb
# Streams the PDF after the business access check; Active Storage's public blob routes are disabled.
class InvoicePdfsController < ApplicationController
  include BusinessScoped

  def show
    invoice = @business.invoices.find(params[:invoice_id])
    return head :not_found unless invoice.pdf.attached?

    send_data invoice.pdf.download, filename: invoice.pdf.filename.to_s, type: "application/pdf", disposition: :inline
  end
end
```

In `app/views/invoices/_form.html.erb`, before the status block:

```erb
  <p><%= f.label :pdf, "PDF (optional)" %> <%= f.file_field :pdf, accept: "application/pdf" %></p>
```

In `app/views/invoices/show.html.erb`, after the `Outstanding` row inside `<dl>`:

```erb
  <% if @invoice.pdf.attached? %>
    <dt>PDF</dt><dd><%= link_to @invoice.pdf.filename.to_s, business_invoice_pdf_path(@business, @invoice) %></dd>
  <% end %>
```

- [ ] **Step 5: Run the specs, then the full suite**

Run: `bundle exec rspec spec/models/invoice_spec.rb spec/requests/invoice_pdfs_spec.rb`
Expected: all pass.
Run: `bundle exec rspec && bin/rubocop && bin/brakeman --no-pager -q`
Expected: 0 failures, clean; no offenses; no warnings (Brakeman's `send_data` check does not flag a blob download).

- [ ] **Step 6: Commit**

```bash
git add app/models/invoice.rb app/controllers/invoices_controller.rb app/controllers/invoice_pdfs_controller.rb app/views/invoices config/routes.rb spec/fixtures/files/invoice.pdf spec/models/invoice_spec.rb spec/requests/invoice_pdfs_spec.rb
git commit -m "Invoices: optional PDF, served after the access check"
```

---

### Task 10: Record payment from the invoice page

**Files:**
- Create: `app/controllers/invoice_payments_controller.rb`
- Create: `app/views/invoice_payments/new.html.erb`, `app/views/invoice_payments/_deposits.html.erb`
- Modify: `config/routes.rb`, `app/views/invoices/_payments.html.erb`, `app/views/invoices/_actions.html.erb`
- Test: `spec/requests/invoice_payments_spec.rb`, `spec/system/invoice_payment_spec.rb`

**Interfaces:**
- Consumes: `InvoicePayments.link/.unlink/.gross_receipts_categories` (Task 6), `Transaction.linkable_deposits`, `.with_unallocated`, `#unallocated_cents` (Task 5), `ScalarParams`, `DateRangeParams#parse_date`.
- Produces: routes `new_business_invoice_payment_path`, `business_invoice_payments_path` (POST; params `deposit_id`, optional `amount`, optional `category_id`), `business_invoice_payment_path` (DELETE). Task 11 adds the `from_inbox=1` branch to `create`.

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/requests/invoice_payments_spec.rb
require "rails_helper"

RSpec.describe "Invoice payments" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business, name: "Checking") }
  let!(:sales) { create(:category, :income, business: business, name: "Sales") }
  let!(:invoice) { create(:invoice, business: business, number: "INV-1042", amount_cents: 120_000) }
  let!(:exact) { create(:transaction, account: account, amount_cents: 120_000, payee: "ACME EXACT", posted_on: Date.current - 3) }
  let!(:recent) { create(:transaction, account: account, amount_cents: 50_000, payee: "ACME RECENT", posted_on: Date.current - 10) }
  let!(:old) { create(:transaction, account: account, amount_cents: 50_000, payee: "ACME OLD", posted_on: Date.current - 200) }

  it "lists exact matches first, then recent deposits, with an older-date filter" do
    sign_in_as user_with_role("editor", business)
    get new_business_invoice_payment_path(business, invoice)
    expect(response.body).to include("ACME EXACT", "ACME RECENT")
    expect(response.body).not_to include("ACME OLD")
    expect(response.body.index("ACME EXACT")).to be < response.body.index("ACME RECENT")

    get new_business_invoice_payment_path(business, invoice, from: (Date.current - 365).iso8601)
    expect(response.body).to include("ACME OLD")
  end

  it "links a deposit and marks the invoice paid" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id }
    expect(response).to redirect_to(business_invoice_path(business, invoice))
    expect(flash[:notice]).to eq("Payment recorded.")
    expect(invoice.reload).to be_paid
  end

  it "records a typed partial amount and rejects amounts that don't parse" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, amount: "abc" }
    expect(flash[:alert]).to eq("Amount is not a valid amount.")
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, amount: "0" }
    expect(flash[:alert]).to eq("Amount must be greater than zero.")
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, amount: "$200.00" }
    expect(invoice.reload.paid_cents).to eq(20_000)
  end

  it "rejects a double submit" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: recent.id }
    post business_invoice_payments_path(business, invoice), params: { deposit_id: recent.id }
    expect(flash[:alert]).to eq("That deposit is already linked to this invoice.")
    expect(InvoicePayment.count).to eq(1)
  end

  it "unlinks a payment" do
    payment = InvoicePayments.link(invoice: invoice, deposit: exact).payment
    sign_in_as user_with_role("editor", business)
    delete business_invoice_payment_path(business, invoice, payment)
    expect(response).to redirect_to(business_invoice_path(business, invoice))
    expect(invoice.reload).to be_sent
  end

  it "won't open the page for drafts" do
    invoice.update!(status: "draft")
    sign_in_as user_with_role("editor", business)
    get new_business_invoice_payment_path(business, invoice)
    expect(response).to redirect_to(business_invoice_path(business, invoice))
    expect(flash[:alert]).to eq("Only sent invoices with a balance can take payments.")
  end

  it "404s for another business's deposit or category" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: create(:transaction, amount_cents: 120_000).id }
    expect(response).to have_http_status(:not_found)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, category_id: create(:category, :income).id }
    expect(response).to have_http_status(:not_found)
    expect(InvoicePayment.count).to eq(0)
  end

  it "forbids viewers and 404s non-members" do
    payment = InvoicePayments.link(invoice: invoice, deposit: recent).payment
    sign_in_as user_with_role("viewer", business)
    get new_business_invoice_payment_path(business, invoice)
    expect(response).to have_http_status(:forbidden)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id }
    expect(response).to have_http_status(:forbidden)
    delete business_invoice_payment_path(business, invoice, payment)
    expect(response).to have_http_status(:forbidden)
    expect(InvoicePayment.count).to eq(1)

    sign_in_as create(:user)
    get new_business_invoice_payment_path(business, invoice)
    expect(response).to have_http_status(:not_found)
  end
end
```

```ruby
# spec/system/invoice_payment_spec.rb
require "rails_helper"

RSpec.describe "Recording an invoice payment" do
  it "links the exact-match deposit and shows the invoice as paid" do
    business = create(:business)
    account = create(:account, business: business, name: "Checking")
    create(:category, :income, business: business, name: "Sales")
    invoice = create(:invoice, business: business, number: "INV-1042", amount_cents: 120_000)
    create(:transaction, account: account, amount_cents: 120_000, payee: "ACME CORP PAYMENT", posted_on: Date.current - 2)

    system_sign_in_as user_with_role("editor", business)
    visit business_invoice_path(business, invoice)
    click_on "Record payment"
    within("#exact-matches") { click_on "Link" }

    expect(page).to have_content("Payment recorded.")
    expect(page).to have_css(".badge-paid")
    expect(page).to have_content("ACME CORP PAYMENT")
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/requests/invoice_payments_spec.rb spec/system/invoice_payment_spec.rb`
Expected: FAIL with `undefined method 'new_business_invoice_payment_path'`.

- [ ] **Step 3: Route and controller**

In `config/routes.rb`, add inside the `resources :invoices do` block, after the `resource :pdf` line:

```ruby
      resources :payments, only: %i[new create destroy], controller: "invoice_payments"
```

```ruby
# app/controllers/invoice_payments_controller.rb
class InvoicePaymentsController < ApplicationController
  include BusinessScoped
  include DateRangeParams
  include ScalarParams

  RECENT_DAYS = 90
  LIMIT = 100

  before_action :require_editor!
  before_action :set_invoice

  def new
    unless @invoice.can_take_payment?
      return redirect_to business_invoice_path(@business, @invoice), alert: "Only sent invoices with a balance can take payments."
    end

    @from = parse_date(params[:from]) || Date.current - RECENT_DAYS
    deposits = Transaction.for_businesses(@business.id).linkable_deposits.includes(:account, :category, :invoice_payments)
    @exact = deposits.with_unallocated(@invoice.outstanding_cents).order(posted_on: :desc, id: :desc).limit(LIMIT).to_a
    @others = deposits.where(posted_on: @from..).where.not(id: @exact.map(&:id)).order(posted_on: :desc, id: :desc).limit(LIMIT).to_a
    @gross_receipts = InvoicePayments.gross_receipts_categories(@business)
    @income_categories = @business.categories.active.income.order(:name)
  end

  def create
    deposit = Transaction.for_businesses(@business.id).find(scalar_params(:deposit_id)[:deposit_id])
    result = link(deposit)
    if result.ok?
      redirect_to business_invoice_path(@business, @invoice), notice: "Payment recorded.", status: :see_other
    else
      redirect_to new_business_invoice_payment_path(@business, @invoice), alert: result.error, status: :see_other
    end
  end

  def destroy
    InvoicePayments.unlink(@invoice.payments.find(params[:id]))
    redirect_to business_invoice_path(@business, @invoice), notice: "Payment unlinked.", status: :see_other
  end

  private

  def set_invoice
    @invoice = @business.invoices.find(params[:invoice_id])
  end

  def link(deposit)
    cents, error = requested_cents
    return InvoicePayments::Result.new(payment: nil, error: error) if error

    category_id = scalar_params(:category_id)[:category_id]
    category = category_id && @business.categories.active.income.find(category_id)
    InvoicePayments.link(invoice: @invoice, deposit: deposit, amount_cents: cents, category: category)
  end

  def requested_cents
    text = scalar_params(:amount)[:amount]
    return [ nil, nil ] if text.nil?

    [ Money.parse(text).cents, nil ]
  rescue Money::ParseError => e
    [ nil, "Amount #{e.message}." ]
  end
end
```

- [ ] **Step 4: Views**

```erb
<%# app/views/invoice_payments/new.html.erb %>
<%= business_nav @business %>
<h1>Record payment for <%= @invoice.number %></h1>
<p><%= @invoice.client.name %> · outstanding <%= money(@invoice.outstanding_cents) %></p>

<h2>Exact matches</h2>
<% if @exact.any? %>
  <%= render "invoice_payments/deposits", id: "exact-matches", deposits: @exact, business: @business, invoice: @invoice,
        gross_receipts: @gross_receipts, income_categories: @income_categories %>
<% else %>
  <p>No deposit matches <%= money(@invoice.outstanding_cents) %> exactly.</p>
<% end %>

<h2>Other deposits since <%= @from %></h2>
<%= form_with url: new_business_invoice_payment_path(@business, @invoice), method: :get, class: "inline-form" do |f| %>
  <%= f.date_field :from, value: @from %>
  <%= f.submit "Show from this date" %>
<% end %>
<% if @others.any? %>
  <%= render "invoice_payments/deposits", id: "other-deposits", deposits: @others, business: @business, invoice: @invoice,
        gross_receipts: @gross_receipts, income_categories: @income_categories %>
<% else %>
  <p>No other unallocated deposits since <%= @from %>.</p>
<% end %>
<%= link_to "Back to invoice", business_invoice_path(@business, @invoice) %>
```

```erb
<%# app/views/invoice_payments/_deposits.html.erb %>
<table id="<%= id %>">
  <thead>
    <tr><th>Date</th><th>Account</th><th>Payee</th><th>Category</th><th class="num">Amount</th><th class="num">Unallocated</th><th></th></tr>
  </thead>
  <tbody>
    <% deposits.each do |deposit| %>
      <tr id="<%= dom_id(deposit, :deposit) %>">
        <td><%= deposit.posted_on %></td>
        <td><%= deposit.account.name %></td>
        <td><%= deposit.payee %></td>
        <td><%= deposit.category&.name || "Uncategorized" %></td>
        <td class="num"><%= money(deposit.amount_cents) %></td>
        <td class="num"><%= money(deposit.unallocated_cents) %></td>
        <td>
          <%= form_with url: business_invoice_payments_path(business, invoice), class: "inline-form" do |f| %>
            <%= hidden_field_tag :deposit_id, deposit.id, id: nil %>
            <%= text_field_tag :amount, Money.new([ deposit.unallocated_cents, invoice.outstanding_cents ].min).to_input,
                  id: nil, size: 10, inputmode: "decimal", aria: { label: "Amount" } %>
            <% if deposit.category_id.nil? && gross_receipts.size != 1 %>
              <%= select_tag :category_id, options_from_collection_for_select(income_categories, :id, :name), id: nil, aria: { label: "Income category" } %>
            <% end %>
            <%= f.submit "Link" %>
          <% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

Replace `app/views/invoices/_payments.html.erb`:

```erb
<h2>Payments</h2>
<% if payments.any? %>
  <table>
    <thead><tr><th>Deposit date</th><th>Account</th><th>Payee</th><th class="num">Amount</th><th></th></tr></thead>
    <tbody>
      <% payments.each do |payment| %>
        <tr id="<%= dom_id(payment) %>">
          <td><%= payment.deposit.posted_on %></td>
          <td><%= payment.deposit.account.name %></td>
          <td><%= payment.deposit.payee %></td>
          <td class="num"><%= money(payment.amount_cents) %></td>
          <td>
            <%= button_to "Unlink", business_invoice_payment_path(@business, invoice, payment), method: :delete, form_class: "inline-form" if current_membership.can_edit? %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% else %>
  <p>No payments linked yet.</p>
<% end %>
```

In `app/views/invoices/_actions.html.erb`, add as the first item inside `<p class="actions">`:

```erb
    <%= link_to "Record payment", new_business_invoice_payment_path(@business, invoice) if invoice.can_take_payment? %>
```

- [ ] **Step 5: Run the specs, then the full suite**

Run: `bundle exec rspec spec/requests/invoice_payments_spec.rb spec/system/invoice_payment_spec.rb`
Expected: all pass.
Run: `bundle exec rspec && bin/rubocop && bin/brakeman --no-pager -q`
Expected: 0 failures, clean; no offenses; no warnings.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/invoice_payments_controller.rb app/views/invoice_payments app/views/invoices/_payments.html.erb app/views/invoices/_actions.html.erb spec/requests/invoice_payments_spec.rb spec/system/invoice_payment_spec.rb
git commit -m "Invoices: record and unlink payments from the invoice page"
```

---
### Task 11: Inbox hint and one-click "Mark paid"

**Files:**
- Create: `app/models/invoice_matcher.rb`, `app/views/inboxes/_invoice_hint.html.erb`
- Modify: `app/views/inboxes/_row.html.erb`, `app/views/inboxes/show.html.erb`, `app/views/household_inboxes/show.html.erb`
- Modify: `app/controllers/inboxes_controller.rb`, `app/controllers/household_inboxes_controller.rb`, `app/controllers/invoice_payments_controller.rb` (`create`)
- Modify: `app/assets/stylesheets/application.css`
- Test: `spec/models/invoice_matcher_spec.rb`, `spec/requests/inbox_invoice_hint_spec.rb`, `spec/system/inbox_invoice_hint_spec.rb`

**Interfaces:**
- Consumes: `Invoice#outstanding_cents`, `InvoicePayments.link`, `InvoicePaymentsController#link` (Task 10).
- Produces: `InvoiceMatcher.for_businesses(business_ids) → InvoiceMatcher`; `InvoiceMatcher#for(txn, business_id) → [Invoice]` (up to `InvoiceMatcher::LIMIT` = 3, oldest due first; `[]` for money out).
- Produces: `inboxes/_row` accepts optional locals `matcher:` and `error:`.
- Produces: `POST business_invoice_payments_path(business, invoice)` with `deposit_id`, `category_id`, `from_inbox=1` → turbo stream `remove` on success, `replace` of the row with the error on failure.

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/models/invoice_matcher_spec.rb
require "rails_helper"

RSpec.describe InvoiceMatcher do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }

  it "matches open invoices by exact outstanding balance in the same business, oldest due first, at most three" do
    due_dates = [ 10, 5, 20, 15 ].map { Date.new(2026, 3, _1) }
    invoices = due_dates.map { create(:invoice, business: business, amount_cents: 50_000, due_date: _1) }
    create(:invoice, business: business, amount_cents: 50_000, status: "draft")
    create(:invoice, amount_cents: 50_000)
    deposit = create(:transaction, account: account, amount_cents: 50_000)

    matches = described_class.for_businesses([ business.id ]).for(deposit, business.id)
    expect(matches).to eq(invoices.values_at(1, 0, 3))
  end

  it "uses the outstanding balance, not the invoice amount" do
    invoice = create(:invoice, business: business, amount_cents: 80_000)
    create(:invoice_payment, invoice: invoice, amount_cents: 30_000)
    matcher = described_class.for_businesses([ business.id ])
    expect(matcher.for(create(:transaction, account: account, amount_cents: 50_000), business.id)).to eq([ invoice ])
    expect(matcher.for(create(:transaction, account: account, amount_cents: 80_000), business.id)).to eq([])
  end

  it "never matches money out" do
    create(:invoice, business: business, amount_cents: 1_000)
    expect(described_class.for_businesses([ business.id ]).for(create(:transaction, account: account, amount_cents: -1_000), business.id)).to eq([])
  end
end
```

```ruby
# spec/requests/inbox_invoice_hint_spec.rb
require "rails_helper"

RSpec.describe "Inbox invoice hint" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business) }
  let!(:sales) { create(:category, :income, business: business, name: "Sales") }
  let!(:client) { create(:client, business: business, name: "Acme") }
  let!(:invoice) { create(:invoice, business: business, client: client, number: "INV-1042", amount_cents: 120_000, due_date: Date.new(2026, 9, 30)) }
  let!(:deposit) { create(:transaction, account: account, amount_cents: 120_000, payee: "ACME CORP") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  it "shows editors the hint on a matching row" do
    sign_in_as user_with_role("editor", business)
    get business_inbox_path(business)
    expect(response.body).to include("Matches", "INV-1042", "Acme", "due Sep 30", "Mark paid")
  end

  it "shows the hint in the household inbox" do
    sign_in_as user_with_role("editor", business)
    get household_inbox_path
    expect(response.body).to include("INV-1042", "Mark paid")
  end

  it "hides the hint from viewers and on rows that don't match" do
    deposit.update!(amount_cents: 119_999)
    sign_in_as user_with_role("editor", business)
    get business_inbox_path(business)
    expect(response.body).not_to include("Mark paid")

    deposit.update!(amount_cents: 120_000)
    sign_in_as user_with_role("viewer", business)
    get business_inbox_path(business)
    expect(response.body).not_to include("Mark paid")
  end

  it "offers a category choice when there are several gross-receipts categories, and a link when there are none" do
    create(:category, :income, business: business, name: "Retail sales")
    sign_in_as user_with_role("editor", business)
    get business_inbox_path(business)
    expect(response.body).to include("Retail sales")

    business.categories.income.update_all(schedule_c_line: "6")
    get business_inbox_path(business)
    expect(response.body).not_to include("Mark paid")
    expect(response.body).to include(new_business_invoice_payment_path(business, invoice))
  end

  it "marks paid with a turbo stream that removes the row" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: deposit.id, category_id: sales.id, from_inbox: "1" }, headers: turbo
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(action="remove" target="transaction_#{deposit.id}"))
    expect(invoice.reload).to be_paid
    expect(deposit.reload.category).to eq(sales)
  end

  it "replaces the row with the error when the invoice was paid meanwhile (double submit)" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: deposit.id, category_id: sales.id, from_inbox: "1" }, headers: turbo
    other = create(:transaction, account: account, amount_cents: 120_000)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: other.id, category_id: sales.id, from_inbox: "1" }, headers: turbo
    expect(response.body).to include(%(action="replace" target="transaction_#{other.id}"))
    expect(response.body).to include("This invoice is already fully paid.")
    expect(InvoicePayment.count).to eq(1)
  end

  it "falls back to a redirect for HTML" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: deposit.id, category_id: sales.id, from_inbox: "1" }
    expect(response).to redirect_to(business_inbox_path(business))
    expect(flash[:notice]).to eq("Payment recorded.")
  end
end
```

```ruby
# spec/system/inbox_invoice_hint_spec.rb
require "rails_helper"

RSpec.describe "Inbox invoice hint", js: true do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business) }
  let!(:sales) { create(:category, :income, business: business, name: "Sales") }
  let!(:invoice) { create(:invoice, business: business, number: "INV-1042", amount_cents: 120_000) }
  let!(:deposit) { create(:transaction, account: account, amount_cents: 120_000, payee: "ACME CORP PAYMENT") }

  it "marks the invoice paid and removes the row without reloading the page" do
    system_sign_in_as user_with_role("editor", business)
    visit business_inbox_path(business)
    page.execute_script("window.__noReload = true")

    row = "#transaction_#{deposit.id}"
    within(row) do
      expect(page).to have_content("Matches INV-1042")
      click_button "Mark paid"
    end

    expect(page).not_to have_css(row)
    expect(page.evaluate_script("window.__noReload")).to be(true)
    expect(invoice.reload).to be_paid
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/invoice_matcher_spec.rb spec/requests/inbox_invoice_hint_spec.rb spec/system/inbox_invoice_hint_spec.rb`
Expected: FAIL with `uninitialized constant InvoiceMatcher` and missing "Mark paid".

- [ ] **Step 3: Matcher**

```ruby
# app/models/invoice_matcher.rb
# Finds open invoices whose outstanding balance equals an inbox deposit's amount.
class InvoiceMatcher
  LIMIT = 3

  def self.for_businesses(business_ids)
    new(Invoice.sent.where(business_id: business_ids).includes(:client, :payments).to_a)
  end

  def initialize(invoices)
    @index = invoices.select { _1.outstanding_cents.positive? }.group_by { [ _1.business_id, _1.outstanding_cents ] }
  end

  def for(txn, business_id)
    return [] unless txn.amount_cents.positive?

    @index.fetch([ business_id, txn.amount_cents ], []).sort_by { [ _1.due_date, _1.id ] }.first(LIMIT)
  end
end
```

- [ ] **Step 4: Controllers**

`app/controllers/inboxes_controller.rb`, add as the last line of `show`:

```ruby
    @matcher = InvoiceMatcher.for_businesses([ @business.id ])
```

`app/controllers/household_inboxes_controller.rb`, add as the last line of `show`:

```ruby
    @matcher = InvoiceMatcher.for_businesses(businesses.map(&:id))
```

`app/controllers/invoice_payments_controller.rb`, replace `create` and add the private `respond_for_inbox`:

```ruby
  def create
    deposit = Transaction.for_businesses(@business.id).find(scalar_params(:deposit_id)[:deposit_id])
    result = link(deposit)
    return respond_for_inbox(result, deposit) if params[:from_inbox] == "1"

    if result.ok?
      redirect_to business_invoice_path(@business, @invoice), notice: "Payment recorded.", status: :see_other
    else
      redirect_to new_business_invoice_payment_path(@business, @invoice), alert: result.error, status: :see_other
    end
  end
```

```ruby
  def respond_for_inbox(result, deposit)
    respond_to do |format|
      format.turbo_stream do
        if result.ok?
          render turbo_stream: turbo_stream.remove(deposit)
        else
          render turbo_stream: turbo_stream.replace(deposit, partial: "inboxes/row", locals: {
            business: @business, txn: deposit.reload, categories: @business.categories.active.order(:name), editable: true,
            matcher: InvoiceMatcher.for_businesses([ @business.id ]), error: result.error
          })
        end
      end
      format.html do
        flash_message = result.ok? ? { notice: "Payment recorded." } : { alert: result.error }
        redirect_back_or_to business_inbox_path(@business), **flash_message
      end
    end
  end
```

- [ ] **Step 5: Views**

Replace `app/views/inboxes/_row.html.erb`:

```erb
<% matches = local_assigns[:matcher] ? matcher.for(txn, business.id) : [] %>
<tr id="<%= dom_id(txn) %>">
  <td><%= txn.posted_on %></td>
  <td><%= txn.account.name %></td>
  <td><%= txn.payee %></td>
  <td class="num"><%= money(txn.amount_cents) %></td>
  <td>
    <% if editable %>
      <%= form_with url: business_transaction_classification_path(business, txn), method: :patch, class: "inline-form" do |f| %>
        <%= f.hidden_field :outcome, value: "categorize" %>
        <%= f.select :category_id, grouped_options_for_select({
              "Income" => categories.select(&:income?).map { [_1.name, _1.id] },
              "Expense" => categories.select(&:expense?).map { [_1.name, _1.id] } }), include_blank: "Category…" %>
        <label><%= f.check_box :make_rule, {}, "1", nil %> make rule</label>
        <%= f.submit "Save" %>
      <% end %>
      <%= button_to "Transfer", business_transaction_classification_path(business, txn), method: :patch, params: { outcome: "transfer" }, form_class: "inline-form" %>
      <%= button_to "Exclude", business_transaction_classification_path(business, txn), method: :patch, params: { outcome: "exclude" }, form_class: "inline-form" %>
      <% if matches.any? %>
        <%= render "inboxes/invoice_hint", business: business, txn: txn, invoices: matches, categories: categories %>
      <% end %>
    <% end %>
    <% if local_assigns[:error] %>
      <p class="errors"><%= error %></p>
    <% end %>
  </td>
</tr>
```

```erb
<%# app/views/inboxes/_invoice_hint.html.erb %>
<% gross_receipts = categories.select { _1.income? && _1.schedule_c_line == "1" } %>
<div class="invoice-hint">
  <% invoices.each do |invoice| %>
    <div>
      Matches <%= link_to invoice.number, business_invoice_path(business, invoice) %> · <%= invoice.client.name %> · due <%= invoice.due_date.strftime("%b %-d") %>
      <% if gross_receipts.empty? %>
        <%= link_to "Record payment", new_business_invoice_payment_path(business, invoice) %>
      <% else %>
        <%= form_with url: business_invoice_payments_path(business, invoice), class: "inline-form" do |f| %>
          <%= hidden_field_tag :deposit_id, txn.id, id: nil %>
          <%= hidden_field_tag :from_inbox, "1", id: nil %>
          <% if gross_receipts.size > 1 %>
            <%= select_tag :category_id, options_from_collection_for_select(gross_receipts, :id, :name), id: nil, aria: { label: "Income category" } %>
          <% else %>
            <%= hidden_field_tag :category_id, gross_receipts.first.id, id: nil %>
          <% end %>
          <%= f.submit "Mark paid" %>
        <% end %>
      <% end %>
    </div>
  <% end %>
</div>
```

In `app/views/inboxes/show.html.erb`, change the row render to pass the matcher:

```erb
      <%= render "inboxes/row", business: @business, txn: txn, categories: @categories, editable: current_membership.can_edit?, matcher: @matcher %>
```

In `app/views/household_inboxes/show.html.erb`, change the row render to:

```erb
        <%= render "inboxes/row", business: business, txn: txn, categories: @categories.fetch(business.id, []),
              editable: @memberships.fetch(business.id).can_edit?, matcher: @matcher %>
```

Append to `app/assets/stylesheets/application.css`:

```css
.invoice-hint { margin-top: .25rem; font-size: .9rem; color: var(--muted); }
```

- [ ] **Step 6: Run the specs, then the full suite**

Run: `bundle exec rspec spec/models/invoice_matcher_spec.rb spec/requests/inbox_invoice_hint_spec.rb spec/system/inbox_invoice_hint_spec.rb spec/requests/inbox_spec.rb spec/system/inbox_categorization_spec.rb`
Expected: all pass (existing inbox specs unchanged).
Run: `bundle exec rspec && bin/rubocop && bin/brakeman --no-pager -q`
Expected: 0 failures, clean; no offenses; no warnings.

- [ ] **Step 7: Commit**

```bash
git add app/models/invoice_matcher.rb app/views/inboxes app/views/household_inboxes/show.html.erb app/controllers/inboxes_controller.rb app/controllers/household_inboxes_controller.rb app/controllers/invoice_payments_controller.rb app/assets/stylesheets/application.css spec/models/invoice_matcher_spec.rb spec/requests/inbox_invoice_hint_spec.rb spec/system/inbox_invoice_hint_spec.rb
git commit -m "Invoices: inbox hint with one-click Mark paid"
```

---

### Task 12: CSV exports, aging report, household invoice list

**Files:**
- Create: `app/models/reports/invoice_csv.rb`, `app/models/reports/invoice_aging_csv.rb`
- Create: `app/controllers/concerns/invoice_aging_report.rb`
- Create: `app/controllers/invoice_agings_controller.rb`, `app/controllers/household_invoice_agings_controller.rb`, `app/controllers/household_invoices_controller.rb`
- Create: `app/views/invoice_agings/show.html.erb`, `app/views/household_invoices/show.html.erb`
- Modify: `app/controllers/invoices_controller.rb` (`index` CSV), `app/views/invoices/index.html.erb`, `config/routes.rb`, `app/views/businesses/_nav.html.erb`, `app/views/layouts/application.html.erb`
- Test: `spec/models/reports/invoice_csv_spec.rb`, `spec/models/reports/invoice_aging_csv_spec.rb`, `spec/requests/invoice_reports_spec.rb`

**Interfaces:**
- Consumes: `Reports::InvoiceAging` (+ `.rows_from`, `.days_past_due`) (Task 3), `Reports::CsvSafe.text`, `InvoiceFilter` (Task 8), `invoices/_table` partial (Task 8), `ScalarParams`.
- Produces: `Reports::InvoiceCsv.generate(invoices, today: Date.current) → String`, `Reports::InvoiceAgingCsv.generate(report, as_of:) → String`.
- Produces routes: `business_invoice_aging_path(business[, format: :csv])`, `household_invoices_path`, `household_invoice_aging_path`, and `business_invoices_path(business, format: :csv, **filters)`.

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/models/reports/invoice_csv_spec.rb
require "rails_helper"

RSpec.describe Reports::InvoiceCsv do
  it "writes one row per invoice with money as plain decimals and neutralized text" do
    business = create(:business, name: "Pat Consulting")
    client = create(:client, business: business, name: "=HYPERLINK(\"x\")")
    invoice = create(:invoice, business: business, client: client, number: "INV-1", amount_cents: 120_000,
                               issue_date: Date.new(2026, 9, 1), due_date: Date.new(2026, 9, 30), description: "+cmd")
    create(:invoice_payment, invoice: invoice, amount_cents: 20_000)

    rows = CSV.parse(described_class.generate([ invoice.reload ], today: Date.new(2026, 10, 6)))
    expect(rows.first).to eq(Reports::InvoiceCsv::HEADERS)
    expect(rows.second).to eq([ "INV-1", "Pat Consulting", "'=HYPERLINK(\"x\")", "2026-09-01", "2026-09-30",
                                "1200.00", "200.00", "1000.00", "overdue", nil, "'+cmd" ])
  end
end
```

```ruby
# spec/models/reports/invoice_aging_csv_spec.rb
require "rails_helper"

RSpec.describe Reports::InvoiceAgingCsv do
  it "writes bucket, invoice, days past due, and outstanding" do
    as_of = Date.new(2026, 10, 6)
    row = Reports::InvoiceAging::Row.new(invoice_id: 1, number: "INV-1", client_name: "Acme", business_name: "Pat Consulting",
                                         due_date: as_of - 45, outstanding_cents: 9_500)
    report = Reports::InvoiceAging.new([ row ], as_of: as_of)
    rows = CSV.parse(described_class.generate(report, as_of: as_of))
    expect(rows).to eq([ Reports::InvoiceAgingCsv::HEADERS, [ "31–60 days", "INV-1", "Pat Consulting", "Acme", "2026-08-22", "45", "95.00" ] ])
  end
end
```

```ruby
# spec/requests/invoice_reports_spec.rb
require "rails_helper"

RSpec.describe "Invoice reports" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:other_business) { create(:business, name: "Jordan Design Studio") }
  let!(:overdue) { create(:invoice, business: business, number: "INV-OLD", due_date: Date.current - 45, issue_date: Date.current - 75) }
  let!(:theirs) { create(:invoice, business: other_business, number: "JDS-1", due_date: Date.current + 10, issue_date: Date.current) }

  def household_user
    create(:user).tap do |user|
      [ business, other_business ].each { create(:membership, user: user, business: _1, role: "viewer") }
    end
  end

  it "shows the business aging report and its CSV to viewers" do
    sign_in_as user_with_role("viewer", business)
    get business_invoice_aging_path(business)
    expect(response.body).to include("31–60 days", "INV-OLD")
    expect(response.body).not_to include("JDS-1")
    get business_invoice_aging_path(business, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("INV-OLD")
  end

  it "exports the filtered invoice list as CSV" do
    sign_in_as user_with_role("viewer", business)
    get business_invoices_path(business, format: :csv, status: "overdue")
    expect(response.media_type).to eq("text/csv")
    expect(CSV.parse(response.body).map(&:first)).to eq([ "Number", "INV-OLD" ])
  end

  it "shows household invoices and aging across businesses" do
    sign_in_as household_user
    get household_invoices_path
    expect(response.body).to include("INV-OLD", "JDS-1", "Jordan Design Studio")
    get household_invoice_aging_path
    expect(response.body).to include("INV-OLD", "JDS-1")
    get household_invoices_path(format: :csv)
    expect(response.body).to include("JDS-1")
  end

  it "404s household screens for users missing a business" do
    sign_in_as user_with_role("owner", business)
    get household_invoices_path
    expect(response).to have_http_status(:not_found)
    get household_invoice_aging_path
    expect(response).to have_http_status(:not_found)
  end

  it "404s the business aging report for non-members" do
    sign_in_as create(:user)
    get business_invoice_aging_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/reports/invoice_csv_spec.rb spec/models/reports/invoice_aging_csv_spec.rb spec/requests/invoice_reports_spec.rb`
Expected: FAIL with `uninitialized constant Reports::InvoiceCsv` / missing route helpers.

- [ ] **Step 3: CSV writers**

```ruby
# app/models/reports/invoice_csv.rb
require "csv"

module Reports
  module InvoiceCsv
    HEADERS = [ "Number", "Business", "Client", "Issue date", "Due date", "Amount", "Paid", "Outstanding", "Status", "Paid on", "Description" ].freeze

    def self.generate(invoices, today: Date.current)
      CSV.generate do |csv|
        csv << HEADERS
        invoices.each do |invoice|
          csv << [
            CsvSafe.text(invoice.number), CsvSafe.text(invoice.business.name), CsvSafe.text(invoice.client.name),
            invoice.issue_date.iso8601, invoice.due_date.iso8601, Money.new(invoice.amount_cents).to_input,
            Money.new(invoice.paid_cents).to_input, Money.new(invoice.outstanding_cents).to_input,
            invoice.display_status(today), invoice.paid_on&.iso8601, CsvSafe.text(invoice.description)
          ]
        end
      end
    end
  end
end
```

```ruby
# app/models/reports/invoice_aging_csv.rb
require "csv"

module Reports
  module InvoiceAgingCsv
    HEADERS = [ "Bucket", "Number", "Business", "Client", "Due date", "Days past due", "Outstanding" ].freeze

    def self.generate(report, as_of:)
      CSV.generate do |csv|
        csv << HEADERS
        report.buckets.each do |bucket|
          bucket.rows.each do |row|
            csv << [ bucket.label, CsvSafe.text(row.number), CsvSafe.text(row.business_name), CsvSafe.text(row.client_name),
                     row.due_date.iso8601, InvoiceAging.days_past_due(row.due_date, as_of), Money.new(row.outstanding_cents).to_input ]
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Routes and controllers**

In `config/routes.rb`, inside `resources :businesses ... do` after the `reports/transactions` line:

```ruby
    get "reports/aging", to: "invoice_agings#show", as: :invoice_aging
```

and inside `scope "household", as: "household" do`:

```ruby
    get "invoices", to: "household_invoices#show", as: :invoices
    get "aging", to: "household_invoice_agings#show", as: :invoice_aging
```

```ruby
# app/controllers/concerns/invoice_aging_report.rb
# Shared by the business and household aging screens; they differ only in which invoices they pass in.
module InvoiceAgingReport
  private

  def render_aging(invoices, title:, filename:)
    today = Date.current
    open_invoices = invoices.sent.includes(:client, :business, :payments).to_a.select { _1.outstanding_cents.positive? }
    @report = Reports::InvoiceAging.new(Reports::InvoiceAging.rows_from(open_invoices), as_of: today)
    @title = title
    respond_to do |format|
      format.html { render "invoice_agings/show" }
      format.csv do
        send_data Reports::InvoiceAgingCsv.generate(@report, as_of: today), filename: "#{filename}-aging-#{today}.csv", type: "text/csv"
      end
    end
  end
end
```

```ruby
# app/controllers/invoice_agings_controller.rb
class InvoiceAgingsController < ApplicationController
  include BusinessScoped
  include InvoiceAgingReport

  def show
    @csv_path = business_invoice_aging_path(@business, format: :csv)
    render_aging(@business.invoices, title: "Aging: #{@business.name}", filename: @business.name.parameterize)
  end
end
```

```ruby
# app/controllers/household_invoice_agings_controller.rb
class HouseholdInvoiceAgingsController < ApplicationController
  include InvoiceAgingReport

  before_action :require_household_access!

  def show
    @csv_path = household_invoice_aging_path(format: :csv)
    render_aging(Invoice.where(business_id: Business.select(:id)), title: "Aging: all businesses", filename: "household")
  end
end
```

```ruby
# app/controllers/household_invoices_controller.rb
class HouseholdInvoicesController < ApplicationController
  include ScalarParams

  before_action :require_household_access!

  def show
    @filter = InvoiceFilter.new(Invoice.where(business_id: Business.select(:id)), scalar_params(:status, :from, :to, :page))
    respond_to do |format|
      format.html { @invoices = @filter.results }
      format.csv { send_data Reports::InvoiceCsv.generate(@filter.all), filename: "household-invoices-#{Date.current}.csv", type: "text/csv" }
    end
  end
end
```

In `app/controllers/invoices_controller.rb`, replace `index`:

```ruby
  def index
    @filter = InvoiceFilter.new(@business.invoices, scalar_params(:status, :client_id, :from, :to, :page))
    respond_to do |format|
      format.html { @invoices = @filter.results }
      format.csv do
        send_data Reports::InvoiceCsv.generate(@filter.all), filename: "#{@business.name.parameterize}-invoices-#{Date.current}.csv", type: "text/csv"
      end
    end
  end
```

- [ ] **Step 5: Views and navigation**

```erb
<%# app/views/invoice_agings/show.html.erb %>
<%= business_nav @business if @business %>
<h1><%= @title %></h1>
<p>As of <%= Date.current %> · total outstanding <%= money(@report.total_cents) %> · <%= link_to "Download CSV", @csv_path %></p>
<% @report.buckets.each do |bucket| %>
  <h2><%= bucket.label %>: <%= money(bucket.total_cents) %></h2>
  <% if bucket.rows.any? %>
    <table>
      <thead><tr><th>Number</th><th>Business</th><th>Client</th><th>Due</th><th class="num">Days past due</th><th class="num">Outstanding</th></tr></thead>
      <tbody>
        <% bucket.rows.each do |row| %>
          <tr>
            <td><%= row.number %></td>
            <td><%= row.business_name %></td>
            <td><%= row.client_name %></td>
            <td><%= row.due_date %></td>
            <td class="num"><%= Reports::InvoiceAging.days_past_due(row.due_date, Date.current) %></td>
            <td class="num"><%= money(row.outstanding_cents) %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>
<% end %>
```

```erb
<%# app/views/household_invoices/show.html.erb %>
<h1>Invoices: all businesses</h1>
<p>
  Outstanding <%= money(@filter.outstanding_cents) %> · Overdue <%= money(@filter.overdue_cents) %> ·
  <%= link_to "Aging", household_invoice_aging_path %> ·
  <%= link_to "Download CSV", household_invoices_path(@filter.params.merge(format: :csv)) %>
</p>
<%= form_with url: household_invoices_path, method: :get, class: "inline-form no-print" do |f| %>
  <%= f.select :status, invoice_status_filter_options, selected: params[:status] %>
  <%= f.date_field :from, value: params[:from] %>
  <%= f.date_field :to, value: params[:to] %>
  <%= f.submit "Filter" %>
<% end %>
<%= render "invoices/table", invoices: @invoices, show_business: true %>
<p>
  <%= link_to "Previous", household_invoices_path(@filter.params.merge(page: @filter.page - 1)) if @filter.page > 1 %>
  <%= link_to "Next", household_invoices_path(@filter.params.merge(page: @filter.page + 1)) if @filter.next_page? %>
</p>
```

In `app/views/invoices/index.html.erb`, replace the totals paragraph with:

```erb
<p>
  Outstanding <%= money(@filter.outstanding_cents) %> · Overdue <%= money(@filter.overdue_cents) %> ·
  <%= link_to "Aging", business_invoice_aging_path(@business) %> ·
  <%= link_to "Download CSV", business_invoices_path(@business, @filter.params.merge(format: :csv)) %>
</p>
```

In `app/views/businesses/_nav.html.erb`, after the Schedule C item:

```erb
    <li><%= link_to "Aging", business_invoice_aging_path(business) %></li>
```

In `app/views/layouts/application.html.erb`, after the `Household` link:

```erb
          <%= link_to "Invoices", household_invoices_path if Current.user.can_view_household? %>
```

- [ ] **Step 6: Run the specs, then the full suite**

Run: `bundle exec rspec spec/models/reports/invoice_csv_spec.rb spec/models/reports/invoice_aging_csv_spec.rb spec/requests/invoice_reports_spec.rb`
Expected: all pass.
Run: `bundle exec rspec && bin/rubocop && bin/brakeman --no-pager -q`
Expected: 0 failures, clean; no offenses; no warnings.

- [ ] **Step 7: Commit**

```bash
git add app/models/reports/invoice_csv.rb app/models/reports/invoice_aging_csv.rb app/controllers/concerns/invoice_aging_report.rb app/controllers/invoice_agings_controller.rb app/controllers/household_invoice_agings_controller.rb app/controllers/household_invoices_controller.rb app/controllers/invoices_controller.rb app/views/invoice_agings app/views/household_invoices app/views/invoices/index.html.erb app/views/businesses/_nav.html.erb app/views/layouts/application.html.erb config/routes.rb spec/models/reports/invoice_csv_spec.rb spec/models/reports/invoice_aging_csv_spec.rb spec/requests/invoice_reports_spec.rb
git commit -m "Invoices: CSV exports, aging report, household invoice list"
```

---

### Task 13: Outstanding and overdue on the dashboard and business page

**Files:**
- Modify: `app/models/invoice.rb` (class method), `app/controllers/dashboards_controller.rb`, `app/controllers/businesses_controller.rb` (`show`)
- Create: `app/views/invoices/_receivables.html.erb`
- Modify: `app/views/dashboards/show.html.erb`, `app/views/businesses/show.html.erb`
- Test: `spec/models/invoice_spec.rb` (add), `spec/requests/receivables_spec.rb`

**Interfaces:**
- Produces: `Invoice.receivables_by_business(business_ids, today: Date.current) → Hash{business_id => { outstanding_cents:, overdue_cents: }}` (sent invoices only; businesses without sent invoices are absent).
- Produces: partial `invoices/_receivables` (local `totals:`, may be nil).

- [ ] **Step 1: Write the failing specs**

Add to `spec/models/invoice_spec.rb`:

```ruby
  describe ".receivables_by_business" do
    it "sums outstanding and overdue over sent invoices per business" do
      create(:invoice, business: business, amount_cents: 10_000, due_date: today + 5)
      late = create(:invoice, business: business, amount_cents: 30_000, due_date: today - 1)
      create(:invoice_payment, invoice: late, amount_cents: 5_000)
      create(:invoice, business: business, amount_cents: 99_000, status: "draft")

      totals = Invoice.receivables_by_business([ business.id ], today: today)
      expect(totals).to eq(business.id => { outstanding_cents: 35_000, overdue_cents: 25_000 })
    end
  end
```

```ruby
# spec/requests/receivables_spec.rb
require "rails_helper"

RSpec.describe "Receivables summary" do
  let!(:business) { create(:business, name: "Pat Consulting") }

  it "shows outstanding and overdue on the dashboard and the business page" do
    create(:invoice, business: business, amount_cents: 120_000, due_date: Date.current - 3)
    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(response.body).to include("Outstanding $1,200.00", "Overdue $1,200.00")
    get business_path(business)
    expect(response.body).to include("Outstanding $1,200.00")
  end

  it "shows nothing when nothing is owed" do
    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(response.body).not_to include("Outstanding")
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/invoice_spec.rb spec/requests/receivables_spec.rb`
Expected: FAIL with `undefined method 'receivables_by_business'` and missing text.

- [ ] **Step 3: Implement**

In `app/models/invoice.rb`, before `def paid_cents`:

```ruby
  def self.receivables_by_business(business_ids, today: Date.current)
    sent.where(business_id: business_ids).includes(:payments).group_by(&:business_id).transform_values do |invoices|
      { outstanding_cents: invoices.sum(&:outstanding_cents),
        overdue_cents: invoices.select { _1.overdue?(today) }.sum(&:outstanding_cents) }
    end
  end
```

`app/controllers/dashboards_controller.rb`, `show` becomes:

```ruby
  def show
    @businesses = Current.user.accessible_businesses.active.order(:name)
    @receivables = Invoice.receivables_by_business(@businesses.map(&:id))
  end
```

`app/controllers/businesses_controller.rb`, `show` becomes:

```ruby
  def show
    @accounts = @business.accounts.active.order(:name)
    @receivables = Invoice.receivables_by_business([ @business.id ])[@business.id]
  end
```

```erb
<%# app/views/invoices/_receivables.html.erb %>
<% if totals && totals[:outstanding_cents].positive? %>
  <span class="receivables">
    Outstanding <%= money(totals[:outstanding_cents]) %><% if totals[:overdue_cents].positive? %> · Overdue <%= money(totals[:overdue_cents]) %><% end %>
  </span>
<% end %>
```

In `app/views/dashboards/show.html.erb`, change the list item to:

```erb
    <li><%= link_to business.name, business_path(business) %> <%= render "invoices/receivables", totals: @receivables[business.id] %></li>
```

In `app/views/businesses/show.html.erb`, after the `Taxpayer` paragraph:

```erb
<p><%= render "invoices/receivables", totals: @receivables %></p>
```

- [ ] **Step 4: Run the specs, then the full suite**

Run: `bundle exec rspec spec/models/invoice_spec.rb spec/requests/receivables_spec.rb`
Expected: pass.
Run: `bundle exec rspec && bin/rubocop`
Expected: 0 failures, clean; no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/models/invoice.rb app/controllers/dashboards_controller.rb app/controllers/businesses_controller.rb app/views/invoices/_receivables.html.erb app/views/dashboards/show.html.erb app/views/businesses/show.html.erb spec/models/invoice_spec.rb spec/requests/receivables_spec.rb
git commit -m "Invoices: outstanding and overdue on dashboard and business page"
```

---

### Task 14: Demo data

**Files:**
- Modify: `lib/demo_seeder.rb`
- Test: `spec/lib/demo_seeder_spec.rb` (add one example)

**Interfaces:**
- Consumes: `InvoicePayments.link` (Task 6), `InvoiceMatcher` (Task 11), `Reports::InvoiceAging` (Task 3).

Demo shape per business: 3 clients (the existing payer plus two others); one paid invoice per categorized monthly payer deposit (linked through `InvoicePayments.link`, so status and `paid_on` come from the real code path); one partially paid overdue invoice; open invoices 10, 45, and 75 days past due; one current; one draft; one void; and one open invoice with an **uncategorized inbox deposit for exactly its amount**, so the inbox hint shows up in the demo.

- [ ] **Step 1: Write the failing spec**

Add to `spec/lib/demo_seeder_spec.rb`:

```ruby
  it "seeds clients and invoices in every state, with inbox deposits that match open invoices" do
    run
    expect(Client.count).to eq(6)
    expect(Invoice.paid.count).to be >= 20
    expect(Invoice.paid.all? { _1.paid_cents == _1.amount_cents && _1.paid_on.present? }).to be(true)
    expect(Invoice.sent.select(&:partial?).size).to eq(2)
    expect(Invoice.draft.count).to eq(2)
    expect(Invoice.void.count).to eq(2)

    report = Reports::InvoiceAging.new(Reports::InvoiceAging.rows_from(Invoice.sent.to_a), as_of: today)
    expect(report.buckets.select { _1.rows.any? }.map(&:key)).to eq(%w[current days_1_30 days_31_60 over_60])

    matcher = InvoiceMatcher.for_businesses(Business.ids)
    hinted = Transaction.inbox.includes(:account).select { matcher.for(_1, _1.account.business_id).any? }
    expect(hinted.size).to eq(2)
  end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb`
Expected: the new example FAILS (`Client.count` is 0).

- [ ] **Step 3: Implement**

In `lib/demo_seeder.rb`, replace the two `seed_business(...)` calls at the end of `build` with:

```ruby
    seed_business(consulting, client: "ACME CORP", income_cents: 850_000, software: [ "ADOBE CREATIVE CLOUD", 5_499 ])
    seed_business(studio, client: "BLUE OX DESIGN CO", income_cents: 520_000, software: [ "FIGMA", 1_500 ])
    seed_invoices(consulting, payer: "ACME CORP", others: [ "Northwind Traders", "Globex" ], prefix: "INV-")
    seed_invoices(studio, payer: "BLUE OX DESIGN CO", others: [ "Initech", "Umbrella Bakery" ], prefix: "JDS-")
```

and add this private method after `seed_business`:

```ruby
  def seed_invoices(business, payer:, others:, prefix:)
    bank = business.accounts.find_by!(name: "Business Checking")
    sales = business.categories.find_by!(name: "Sales")
    payer_client, second, third = ([ payer.titleize ] + others).map { business.clients.create!(name: _1) }
    count = 0
    add_invoice = lambda do |client, cents, issued, status: "sent"|
      count += 1
      business.invoices.create!(client: client, number: format("%s%04d", prefix, count), issue_date: issued, due_date: issued + 30,
                                amount_cents: cents, status: status, description: "Professional services")
    end

    # Each categorized monthly payment pays the invoice issued about a month earlier.
    bank.transactions.where(payee: "#{payer} PAYMENT").where.not(category_id: nil).order(:posted_on).each do |deposit|
      InvoicePayments.link(invoice: add_invoice.(payer_client, deposit.amount_cents, deposit.posted_on - 25), deposit: deposit)
    end

    partial_deposit = bank.transactions.create!(posted_on: @today - 20, payee: "#{second.name.upcase} PAYMENT", amount_cents: 100_000,
                                                category: sales, categorized_by: "user", external_id: "demo-#{business.id}-partial")
    InvoicePayments.link(invoice: add_invoice.(second, 300_000, @today - 50), deposit: partial_deposit)

    add_invoice.(third, 180_000, @today - 40)
    add_invoice.(second, 95_000, @today - 75)
    add_invoice.(third, 60_000, @today - 105)
    add_invoice.(payer_client, 220_000, @today - 5)
    add_invoice.(third, 75_000, @today, status: "draft")
    add_invoice.(second, 40_000, @today - 60, status: "void")

    # An uncategorized deposit in the inbox for exactly an open invoice's amount, so the inbox shows its "Mark paid" hint.
    match = add_invoice.(third, 245_000, @today - 20)
    bank.transactions.create!(posted_on: @today, payee: "#{third.name.upcase} ACH", amount_cents: match.amount_cents,
                              external_id: "demo-#{business.id}-match")
  end
```

- [ ] **Step 4: Run the seeder spec and try it for real**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb`
Expected: all pass (existing examples too: `Transaction.inbox.count > 0` still holds).
Run: `bin/rails demo:reset`
Expected: completes and prints the logins; no exceptions.

- [ ] **Step 5: Full suite and commit**

Run: `bundle exec rspec && bin/rubocop`
Expected: 0 failures, clean; no offenses.

```bash
git add lib/demo_seeder.rb spec/lib/demo_seeder_spec.rb
git commit -m "Demo: clients and invoices in every state, with an inbox match"
```

---

### Task 15: Verify, document, open the PR, and get CI green

**Files:**
- Modify: `README.md` (one line in the intro)
- Possibly modify: `.github/workflows/ci.yml` (Chrome setup fallback from Task 1)

- [ ] **Step 1: README**

In `README.md`, change the first paragraph's feature list to include invoices:

```markdown
Self-hosted bookkeeping for a freelancing household: income and expenses per business, CSV imports, a rules-driven categorization inbox, invoice tracking with payments linked to deposits, mileage, P&L and Schedule C reports, and role-based sharing with your accountant. Design: `docs/superpowers/specs/2026-10-05-goodbooks-design.md` (invoices: `docs/superpowers/specs/2026-10-06-goodbooks-invoices-design.md`).
```

- [ ] **Step 2: Run every CI check locally**

Run: `bundle exec rspec`
Expected: 0 failures; output is only the RSpec reporter (no log lines, warnings, or deprecations).
Run: `bin/rubocop -f github`
Expected: no offenses.
Run: `bin/brakeman --no-pager`
Expected: `No warnings found`.
Run: `bin/bundler-audit`
Expected: `No vulnerabilities found`.
Run: `bin/importmap audit`
Expected: no vulnerable packages.

- [ ] **Step 3: Click through the demo**

Run: `bin/rails demo:reset && bin/dev`, sign in as `pat@example.com` (password and TOTP secret printed by the seeder), and check: the dashboard shows Outstanding/Overdue; the inbox shows a "Matches … Mark paid" hint and clicking it removes the row; the invoice list filters by Overdue; an invoice page shows Record payment and Unlink; the aging report shows all four buckets; the household Invoices link works. Stop `bin/dev` afterwards.

- [ ] **Step 4: Commit, push, open the PR**

```bash
git add README.md
git commit -m "README: mention invoices"
git push -u origin invoices
gh pr create --base main --head invoices --title "Invoices (sub-project 2) + green CI" --body "$(cat <<'EOF'
## Summary
- Clients, invoices (draft/sent/paid/void; partial and overdue derived), optional PDF
- Payments link invoices to deposits from the invoice page (exact matches first) or from the inbox ("Mark paid"), through one locked service; linked deposits are guarded
- Invoice list + CSV (business and household), aging report + CSV, dashboard outstanding/overdue, demo data
- CI: Brakeman warning fixed (scalar filters), RSpec job added, bundler-audit clean

Spec: docs/superpowers/specs/2026-10-06-goodbooks-invoices-design.md
Plan: docs/superpowers/plans/2026-10-06-goodbooks-invoices.md

## Test plan
- [ ] CI: scan_ruby, scan_js, lint, test all green
- [ ] bin/rails demo:reset; inbox Mark paid; Record payment; aging buckets

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01VdQWdubZ6L19ekyi7gz8GK
EOF
)"
```

- [ ] **Step 5: Watch CI until every check is green**

Run: `gh pr checks --watch`
Expected: `scan_ruby`, `scan_js`, `lint`, `test` all pass.
If `test` fails because Chrome/chromedriver is unavailable, add the `browser-actions/setup-chrome@v2` step from Task 1 Step 6, commit ("CI: install Chrome for system specs"), push, and watch again. For any other failure, use superpowers:systematic-debugging; do not mark this task done until every check is green.

- [ ] **Step 6: Update Kaneo**

Comment on GB-3 with the PR link and the final check results, and move GB-3 to In Review.
