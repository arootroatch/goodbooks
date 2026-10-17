# Sharing Polish (Sub-project 7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Session management, household user deactivation, an append-only audit log of people's edits, an owner-only error log, and Docker log rotation.

**Architecture:** An `Audited` model concern writes `AuditEvent` rows from `after_create/update/destroy` callbacks whenever `Current.actor` is set and no `Audit.summarize` block is open; bulk actions write one summary event. Sessions gain `last_seen_at`; users gain `deactivated_at`, checked at sign-in, 2FA and cookie lookup. A `Rails.error` subscriber groups unhandled exceptions into `ErrorEvent` rows.

**Tech Stack:** Rails 8.1, SQLite, RSpec + FactoryBot + Capybara, Hotwire. No new gems.

**Spec:** `docs/superpowers/specs/2026-10-14-goodbooks-sharing-polish-design.md`

## Global Constraints

- No new gems. No email of any kind.
- Audit events are written only when `Current.actor` is present (a signed-in user, or `Audit.as(user)`); background jobs write none.
- Audit events are append-only: no update or destroy routes; persisted rows are read-only.
- `Audit::SECRETS = %w[digest token secret otp password crypt salt]` — any attribute name containing one is stored as `"[FILTERED]"` on both sides.
- Ignored attributes: `id`, `created_at`, `updated_at`, plus per-model `ignore:`.
- Covered models (exactly): Business, Person, Membership, Invite, Household, Account, Transaction, Category, Rule, MileageEntry, Client, Invoice, InvoicePayment, SalesTaxProfile, SalesTaxFiling, TaxYear, HomeOffice, PersonAdjustment, EstimatedPayment, TaxParameters, Goal, PlaidItem.
- `Session::TOUCH_INTERVAL = 5.minutes`.
- Users, Audit log and Errors pages: household owner only, 403 otherwise (`require_household_owner!`). Sessions page: every user, own sessions only; another user's session id → 404.
- Error messages truncated to 1,000 characters; backtrace capped at 30 cleaned lines; request params, headers and cookies are never stored.
- Docker logging: `json-file`, `max-size: "10m"`, `max-file: "5"`.
- Every task ends with `bin/rubocop` clean on touched files; the final task runs every CI check (`bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/importmap audit`, `bin/rubocop`, `bundle exec rspec`).
- Flash copy and page text match the spec verbatim where the spec gives it.

## Review Focus

1. **A deactivated user with a live cookie** must be signed out on their very next request, not just blocked at sign-in — tested in Task 7.
2. **Revoking your current session from the Sessions list** must behave like signing out (cookie cleared, sent to sign-in), not leave a dangling cookie — tested in Task 6.
3. **An invite accepted during sign-up** must still be audited with the new user as the actor, even though no session exists yet — tested in Task 3.
4. **Nested summaries** (creating a book inside another summarized action, rules applied inside a CSV commit) must write exactly one event — tested in Tasks 1 and 3.
5. **The error subscriber failing** (e.g. a validation error while saving the ErrorEvent) must never turn one 500 into a different exception or a loop — tested in Task 9.

---

## File Structure

| File | Responsibility |
|---|---|
| `db/migrate/20261015000001_create_audit_events.rb` | audit table |
| `db/migrate/20261015000002_add_last_seen_at_to_sessions.rb` | session activity |
| `db/migrate/20261015000003_add_deactivated_at_to_users.rb` | deactivation |
| `db/migrate/20261015000004_create_error_events.rb` | error table |
| `app/models/current.rb` | `audit_actor`, `audit_summary`, `actor` |
| `app/models/audit.rb` | `record`, `as`, `summarize`, `note`, `filter`, `MODELS`, `SECRETS` |
| `app/models/concerns/audited.rb` | callbacks + `audited` macro |
| `app/models/audit_event.rb` | read-only event row, `filtered` |
| `app/models/user_agent_label.rb` | "Safari on iOS" |
| `app/models/user/deactivation.rb` | remove-from-household rules and transaction |
| `app/models/error_event.rb`, `app/models/error_log.rb`, `config/initializers/error_log.rb` | error capture |
| `app/controllers/audit_events_controller.rb`, `app/helpers/audit_events_helper.rb`, `app/views/audit_events/index.html.erb` | audit page |
| `app/controllers/sessions_list_controller.rb`, `app/views/sessions_list/index.html.erb` | sessions page |
| `app/controllers/users_controller.rb`, `app/views/users/index.html.erb` | users page |
| `app/controllers/error_events_controller.rb`, `app/views/error_events/index.html.erb` | errors page |
| `app/helpers/navigation_helper.rb`, `app/views/layouts/_sidebar.html.erb` | links |
| 22 model files | `include Audited` + `audited ...` |

---

### Task 1: Audit core (table, Current, Audit, Audited, AuditEvent)

**Files:**
- Create: `db/migrate/20261015000001_create_audit_events.rb`, `app/models/audit.rb`, `app/models/concerns/audited.rb`, `app/models/audit_event.rb`
- Modify: `app/models/current.rb`, `app/models/rule.rb` (first audited model, used by the specs)
- Test: `spec/models/audit_spec.rb`, `spec/models/audit_event_spec.rb`

**Interfaces:**
- Produces: `Current.actor`, `Current.audit_actor`, `Current.audit_summary`; `Audit.as(user) { }`, `Audit.record(record, action)`, `Audit.summarize(record: nil, business: nil) { |summary| summary.text = ...; summary.record = ...; summary.business = ... }` (returns the block's value), `Audit.note(text, record: nil, business: nil)`, `Audit.filter(hash)`, `Audit::MODELS`, `Audit::SECRETS`, `Audit::FILTERED`; model macro `audited(label: -> { }, business: -> { }, ignore: [])`; instance `#audit_label`, `#audit_business_id`, `#audit_values(action)`, private hook `#audit_extra_values(action)` returning a hash; `AuditEvent.filtered(user_id:, auditable_type:, auditable_id:, business_id:, range:)`.

- [ ] **Step 1: Write the migration and run it**

```ruby
# db/migrate/20261015000001_create_audit_events.rb
class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.string :auditable_type
      t.integer :auditable_id
      t.integer :business_id
      t.string :label, null: false, default: ""
      t.json :changed_values, null: false, default: {}
      t.string :summary
      t.datetime :created_at, null: false
    end
    add_index :audit_events, :created_at
    add_index :audit_events, %i[user_id created_at]
    add_index :audit_events, %i[auditable_type auditable_id]
    add_index :audit_events, %i[business_id created_at]
  end
end
```

Run: `bin/rails db:migrate` — Expected: `db/schema.rb` gains `audit_events`.

- [ ] **Step 2: Write the failing specs**

```ruby
# spec/models/audit_spec.rb
require "rails_helper"

RSpec.describe Audit do
  let(:business) { create(:business) }
  let(:actor) { create(:user, name: "Alex") }

  it "writes nothing without an actor" do
    expect { create(:rule, business: business) }.not_to change(AuditEvent, :count)
  end

  it "records a create with the new values, the label and the book" do
    rule = Audit.as(actor) { create(:rule, business: business, value: "stripe") }
    event = AuditEvent.last
    expect(event).to have_attributes(user: actor, action: "create", auditable_type: "Rule", auditable_id: rule.id,
                                     business_id: business.id, label: "Rule: payee contains \"stripe\"")
    expect(event.changed_values["value"]).to eq([ nil, "stripe" ])
    expect(event.changed_values.keys).not_to include("id", "created_at", "updated_at")
  end

  it "records an update with before and after, and skips an update that changed nothing tracked" do
    rule = create(:rule, business: business, value: "adobe")
    Audit.as(actor) { rule.update!(value: "figma") }
    expect(AuditEvent.last.changed_values).to eq("value" => [ "adobe", "figma" ])
    expect { Audit.as(actor) { rule.touch } }.not_to change(AuditEvent, :count)
    expect { Audit.as(actor) { rule.save! } }.not_to change(AuditEvent, :count)
  end

  it "records a destroy with the old values" do
    rule = create(:rule, business: business, value: "adobe")
    Audit.as(actor) { rule.destroy! }
    expect(AuditEvent.last).to have_attributes(action: "destroy", auditable_id: rule.id)
    expect(AuditEvent.last.changed_values["value"]).to eq([ "adobe", nil ])
  end

  it "filters secret-looking attribute names" do
    expect(Audit.filter("token_digest" => [ nil, "abc" ], "access_token" => [ "a", "b" ], "email" => [ nil, "x@y.z" ]))
      .to eq("token_digest" => [ "[FILTERED]", "[FILTERED]" ], "access_token" => [ "[FILTERED]", "[FILTERED]" ], "email" => [ nil, "x@y.z" ])
  end

  it "scopes the actor override to the block" do
    Audit.as(actor) { expect(Current.actor).to eq(actor) }
    expect(Current.actor).to be_nil
  end

  describe ".summarize" do
    it "writes one summary event instead of per-row events, and returns the block's value" do
      result = Audit.as(actor) do
        Audit.summarize(business: business) do |summary|
          create(:rule, business: business)
          create(:rule, business: business)
          summary.text = "Did two things"
          :done
        end
      end
      expect(result).to eq(:done)
      expect(AuditEvent.pluck(:action, :summary, :business_id)).to eq([ [ "summary", "Did two things", business.id ] ])
    end

    it "writes only the outermost summary when nested" do
      Audit.as(actor) do
        Audit.summarize do |outer|
          Audit.summarize { |inner| inner.text = "inner" }
          outer.text = "outer"
        end
      end
      expect(AuditEvent.pluck(:summary)).to eq([ "outer" ])
    end

    it "writes nothing when the block raises" do
      expect do
        Audit.as(actor) { Audit.summarize { |s| s.text = "x"; raise "boom" } }
      end.to raise_error("boom")
      expect(AuditEvent.count).to eq(0)
    end

    it "writes nothing without an actor, and still suppresses rows" do
      Audit.summarize { |s| create(:rule, business: business); s.text = "x" }
      expect(AuditEvent.count).to eq(0)
    end

    it "labels the summary with its record" do
      rule = create(:rule, business: business, value: "adobe")
      Audit.as(actor) { Audit.summarize(record: rule) { |s| s.text = "Reordered rules" } }
      expect(AuditEvent.last).to have_attributes(auditable_type: "Rule", auditable_id: rule.id, business_id: business.id,
                                                 label: "Rule: payee contains \"adobe\"")
    end
  end

  describe ".note" do
    it "labels a non-audited record by its name" do
      target = create(:user, name: "Avery")
      Audit.as(actor) { Audit.note("Removed Avery from the household", record: target) }
      expect(AuditEvent.last).to have_attributes(action: "summary", auditable_type: "User", auditable_id: target.id, label: "Avery", business_id: nil)
    end
  end
end
```

```ruby
# spec/models/audit_event_spec.rb
require "rails_helper"

RSpec.describe AuditEvent do
  let(:event) { described_class.create!(user: create(:user), action: "summary", summary: "x") }

  it "can't be updated or destroyed" do
    expect { event.update!(summary: "y") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "filters by user, type, record, book and date range" do
    user = create(:user)
    old = travel_to(Date.new(2026, 1, 5).noon) { described_class.create!(user:, action: "create", auditable_type: "Rule", auditable_id: 1, business_id: 7) }
    recent = described_class.create!(user:, action: "update", auditable_type: "Goal", auditable_id: 2, business_id: 8)
    expect(described_class.filtered(user_id: user.id)).to contain_exactly(old, recent)
    expect(described_class.filtered(auditable_type: "Rule")).to eq([ old ])
    expect(described_class.filtered(auditable_type: "Goal", auditable_id: 2)).to eq([ recent ])
    expect(described_class.filtered(business_id: 8)).to eq([ recent ])
    expect(described_class.filtered(range: Date.new(2026, 1, 1)..Date.new(2026, 1, 31))).to eq([ old ])
  end
end
```

- [ ] **Step 3: Run to verify they fail**

Run: `bundle exec rspec spec/models/audit_spec.rb spec/models/audit_event_spec.rb`
Expected: FAIL — `uninitialized constant Audit` / `AuditEvent`.

- [ ] **Step 4: Implement**

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :audit_actor, :audit_summary
  delegate :user, to: :session, allow_nil: true

  # Who an audit event is attributed to: an explicit override (sign-up, setup), else the signed-in user.
  def actor = audit_actor || user
end
```

```ruby
# app/models/audit.rb
# Writes AuditEvents for people's edits. Audited models call .record from their callbacks; nothing is written without an
# actor (so background jobs write nothing) or inside a .summarize block (which writes one summary event instead).
module Audit
  IGNORED = %w[id created_at updated_at].freeze
  SECRETS = %w[digest token secret otp password crypt salt].freeze
  FILTERED = "[FILTERED]".freeze
  MODELS = %w[Business Person Membership Invite Household Account Transaction Category Rule MileageEntry Client Invoice
              InvoicePayment SalesTaxProfile SalesTaxFiling TaxYear HomeOffice PersonAdjustment EstimatedPayment
              TaxParameters Goal PlaidItem].freeze

  Summary = Struct.new(:text, :record, :business, keyword_init: true)

  def self.as(user, &) = Current.set(audit_actor: user, &)

  def self.record(record, action)
    return if Current.actor.nil? || Current.audit_summary

    values = record.audit_values(action)
    return if action == "update" && values.empty?

    AuditEvent.create!(user: Current.actor, action:, auditable_type: record.class.name, auditable_id: record.id,
                       business_id: record.audit_business_id, label: label_for(record), changed_values: values)
  end

  def self.summarize(record: nil, business: nil)
    return yield(Summary.new) if Current.audit_summary

    summary = Summary.new(record:, business:)
    result = Current.set(audit_summary: summary) { yield summary }
    note(summary.text, record: summary.record, business: summary.business) if summary.text.present?
    result
  end

  def self.note(text, record: nil, business: nil)
    return if Current.actor.nil?

    business_id = business.is_a?(Business) ? business.id : business || record.try(:audit_business_id)
    AuditEvent.create!(user: Current.actor, action: "summary", summary: text, auditable_type: record&.class&.name,
                       auditable_id: record&.id, business_id:, label: label_for(record))
  end

  def self.filter(values)
    values.to_h { |name, pair| [ name, SECRETS.any? { name.to_s.include?(_1) } ? [ FILTERED, FILTERED ] : pair ] }
  end

  def self.label_for(record)
    return "" if record.nil?

    (record.try(:audit_label) || record.try(:name) || "#{record.model_name.human} ##{record.id}").to_s.truncate(255)
  end

  private_class_method :label_for
end
```

```ruby
# app/models/concerns/audited.rb
# Records creates, updates and destroys through Audit. Declare a label and, when the book isn't business_id, how to find it:
#   audited label: -> { name }, business: -> { account&.business_id }, ignore: %w[cursor]
module Audited
  extend ActiveSupport::Concern

  included do
    class_attribute :audit_options, instance_writer: false, default: {}
    after_create { Audit.record(self, "create") }
    after_update { Audit.record(self, "update") }
    after_destroy { Audit.record(self, "destroy") }
  end

  class_methods do
    def audited(label: nil, business: nil, ignore: [])
      self.audit_options = { label:, business:, ignore: ignore.map(&:to_s) }
    end
  end

  def audit_label
    audit_options[:label] ? instance_exec(&audit_options[:label]).to_s : "#{model_name.human} ##{id}"
  end

  def audit_business_id
    return instance_exec(&audit_options[:business]) if audit_options[:business]

    business_id if has_attribute?(:business_id)
  end

  def audit_values(action)
    pairs = case action
    when "update" then saved_changes
    when "create" then attributes.compact.transform_values { [ nil, _1 ] }
    when "destroy" then attributes.compact.transform_values { [ _1, nil ] }
    end
    Audit.filter(pairs.except(*Audit::IGNORED, *audit_options.fetch(:ignore, [])).merge(audit_extra_values(action)))
  end

  private

  def audit_extra_values(_action) = {}
end
```

```ruby
# app/models/audit_event.rb
class AuditEvent < ApplicationRecord
  ACTIONS = %w[create update destroy summary].freeze

  belongs_to :user
  belongs_to :business, optional: true

  validates :action, inclusion: { in: ACTIONS }

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Audit events can't be deleted" }

  def readonly? = persisted? || super

  def self.filtered(user_id: nil, auditable_type: nil, auditable_id: nil, business_id: nil, range: nil)
    scope = all
    scope = scope.where(user_id:) if user_id.present?
    scope = scope.where(auditable_type:) if auditable_type.present?
    scope = scope.where(auditable_id:) if auditable_id.present?
    scope = scope.where(business_id:) if business_id.present?
    scope = scope.where(created_at: range.first.in_time_zone..range.last.in_time_zone.end_of_day) if range
    scope
  end
end
```

In `app/models/rule.rb`, directly under `class Rule < ApplicationRecord`:

```ruby
  include Audited
  audited label: -> { "Rule: #{field} #{operator.to_s.humanize(capitalize: false)} \"#{value}\"" }
```

(`operator` "contains" humanizes to "contains"; "starts_with" to "starts with".)

- [ ] **Step 5: Run to verify they pass**

Run: `bundle exec rspec spec/models/audit_spec.rb spec/models/audit_event_spec.rb spec/models/rule_spec.rb spec/requests/rules_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20261015000001_create_audit_events.rb db/schema.rb app/models/current.rb app/models/audit.rb app/models/concerns/audited.rb app/models/audit_event.rb app/models/rule.rb spec/models/audit_spec.rb spec/models/audit_event_spec.rb
git commit -m "Audit core: AuditEvent, Audited concern, actor and summary blocks"
```

---

### Task 2: Audit every covered model

**Files:**
- Modify: `app/models/{business,person,membership,invite,household,account,transaction,category,mileage_entry,client,invoice,invoice_payment,sales_tax_profile,sales_tax_filing,tax_year,home_office,person_adjustment,estimated_payment,tax_parameters,goal,plaid_item}.rb`
- Test: `spec/models/audit_coverage_spec.rb`

**Interfaces:**
- Consumes: `Audited`, `audited(label:, business:, ignore:)`, `audit_extra_values(action)` (Task 1).
- Produces: every model in `Audit::MODELS` writes events.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/models/audit_coverage_spec.rb
require "rails_helper"

RSpec.describe "Audit coverage" do
  let(:actor) { create(:user) }

  it "audits exactly the models in Audit::MODELS" do
    Rails.application.eager_load!
    audited = ApplicationRecord.descendants.select { _1.include?(Audited) }.map(&:name)
    expect(audited).to match_array(Audit::MODELS)
  end

  it "filters every column a secret filter would catch" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters - %i[email code])
    Audit::MODELS.each do |name|
      name.constantize.column_names.each do |column|
        next if filter.filter(column => "x")[column] == "x"

        expect(Audit.filter(column => [ 1, 2 ])[column]).to eq([ Audit::FILTERED, Audit::FILTERED ]), "#{name}##{column}"
      end
    end
  end

  it "folds an invite's grants into its create event and filters the token digest" do
    business = create(:business, name: "Smith Photography")
    Audit.as(actor) { create(:invite, business: business, role: "editor") }
    values = AuditEvent.find_by!(auditable_type: "Invite").changed_values
    expect(values["grants"]).to eq([ nil, [ "Smith Photography: editor" ] ])
    expect(values["token_digest"]).to eq([ Audit::FILTERED, Audit::FILTERED ])
    expect(AuditEvent.where(auditable_type: "InviteGrant")).to be_empty
  end

  it "finds the book through the account for transactions and through the invoice for payments" do
    account = create(:account)
    Audit.as(actor) { create(:transaction, account: account) }
    expect(AuditEvent.last.business_id).to eq(account.business_id)
  end

  it "labels a business by name and stores its own id as the book" do
    business = create(:business)
    Audit.as(actor) { business.update!(name: "Renamed") }
    expect(AuditEvent.last).to have_attributes(label: "Renamed", business_id: business.id)
  end

  it "ignores Plaid sync bookkeeping and filters the access token" do
    item = create(:plaid_item)
    expect { Audit.as(actor) { item.update!(cursor: "c2", last_synced_at: Time.current) } }.not_to change(AuditEvent, :count)
    Audit.as(actor) { item.update!(access_token: "new-token") }
    expect(AuditEvent.last.changed_values["access_token"]).to eq([ Audit::FILTERED, Audit::FILTERED ])
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/models/audit_coverage_spec.rb`
Expected: FAIL — `audited` list is only `["Rule"]`.

- [ ] **Step 3: Add the macro to each model**

Insert these two lines directly under each `class X < ApplicationRecord` line:

| File | Lines |
|---|---|
| `business.rb` | `include Audited` / `audited label: -> { name }, business: -> { id }` |
| `person.rb` | `include Audited` / `audited label: -> { name }` |
| `membership.rb` | `include Audited` / `audited label: -> { "#{user&.name} in #{business&.name} (#{role})" }` |
| `invite.rb` | `include Audited` / `audited label: -> { "Invite for #{email.presence \|\| "anyone with the link"}" }` |
| `household.rb` | `include Audited` / `audited label: -> { name }` |
| `account.rb` | `include Audited` / `audited label: -> { name }` |
| `transaction.rb` | `include Audited` / `audited label: -> { "#{posted_on} · #{payee} · #{Money.new(amount_cents)}" }, business: -> { account&.business_id }` |
| `category.rb` | `include Audited` / `audited label: -> { name }` |
| `mileage_entry.rb` | `include Audited` / `audited label: -> { "#{driven_on} · #{purpose}" }` |
| `client.rb` | `include Audited` / `audited label: -> { name }` |
| `invoice.rb` | `include Audited` / `audited label: -> { "Invoice #{number}" }` |
| `invoice_payment.rb` | `include Audited` / `audited label: -> { "Payment of #{Money.new(amount_cents)} on invoice #{invoice&.number}" }, business: -> { invoice&.business_id }` |
| `sales_tax_profile.rb` | `include Audited` / `audited label: -> { "Sales tax profile for #{business&.name}" }` |
| `sales_tax_filing.rb` | `include Audited` / `audited label: -> { "Sales tax filing for the period starting #{period_starts_on}" }` |
| `tax_year.rb` | `include Audited` / `audited label: -> { "Tax year #{year}" }` |
| `home_office.rb` | `include Audited` / `audited label: -> { "Home office #{year}" }` |
| `person_adjustment.rb` | `include Audited` / `audited label: -> { "#{person&.name} adjustments #{year}" }` |
| `estimated_payment.rb` | `include Audited` / `audited label: -> { "Estimated payment Q#{quarter} #{tax_year&.year}" }` |
| `tax_parameters.rb` | `include Audited` / `audited label: -> { "Tax parameters #{year}" }` |
| `goal.rb` | `include Audited` / `audited label: -> { name }` |
| `plaid_item.rb` | `include Audited` / `audited label: -> { institution_name }, ignore: %w[cursor last_synced_at]` |

(The `\|\|` in the table is `||` in Ruby.)

Then in `app/models/invite.rb`, at the end of the `private` section:

```ruby
  def audit_extra_values(action)
    return {} unless action == "create"

    { "grants" => [ nil, grants.map { "#{_1.business.name}: #{_1.role}" } ] }
  end
```

- [ ] **Step 4: Run the new spec, then the whole suite**

Run: `bundle exec rspec spec/models/audit_coverage_spec.rb` — Expected: PASS.
Run: `bundle exec rspec` — Expected: PASS. If an existing spec destroys a `User` that now has audit events, the foreign key fails; fix the spec by not giving that user an actor role, never by dropping the FK.

- [ ] **Step 5: Commit**

```bash
git add app/models spec/models/audit_coverage_spec.rb
git commit -m "Audit every covered model; invites carry their grants"
```

---

### Task 3: Actors without a session, and summary call sites

**Files:**
- Modify: `app/forms/setup_form.rb`, `app/controllers/invite_acceptances_controller.rb`, `app/services/business_provisioner.rb`, `app/services/personal_book_provisioner.rb`, `app/controllers/rules_controller.rb`, `app/models/csv_import.rb`, `app/models/rule.rb` (`move_to!`), `app/models/goal.rb` (`move_to!`)
- Test: `spec/models/audit_call_sites_spec.rb`, `spec/requests/audit_actors_spec.rb`

**Interfaces:**
- Consumes: `Audit.as`, `Audit.summarize` (Task 1).

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/models/audit_call_sites_spec.rb
require "rails_helper"

RSpec.describe "Audit summary call sites" do
  let(:business) { create(:business) }
  let(:actor) { create(:user, :household_owner) }

  it "creating a book writes one summary" do
    book = Audit.as(actor) { BusinessProvisioner.call(Household.first.businesses.new(name: "New Co", person: business.person), owner: actor) }
    expect(AuditEvent.pluck(:action, :summary, :business_id)).to eq([ [ "summary", "Created book New Co", book.id ] ])
  end

  it "creating the personal book writes one summary" do
    Audit.as(actor) { PersonalBookProvisioner.call(business.household) }
    expect(AuditEvent.pluck(:summary)).to eq([ "Created the personal book" ])
  end

  it "reordering rules and goals writes one summary each" do
    first, second = create_list(:rule, 2, business: business)
    Audit.as(actor) { second.move_to!(1) }
    goal_a = create(:goal, business: business)
    create(:goal, business: business)
    Audit.as(actor) { goal_a.move_to!(2) }
    expect(AuditEvent.pluck(:summary)).to eq([ "Reordered rules", "Reordered goals" ])
    expect(first.reload.position).to eq(2)
  end

  it "committing a CSV import writes one summary, including the rules it applied" do
    software = create(:category, business: business, name: "Software")
    create(:rule, business: business, value: "adobe", category: software)
    account = create(:account, :csv, business: business, name: "Checking",
      csv_mapping: CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount").to_h)
    import = account.csv_imports.create!(file: Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/checking.csv"), "text/csv"))
    Audit.as(actor) { import.commit! }
    expect(AuditEvent.pluck(:action)).to eq([ "summary" ])
    expect(AuditEvent.last.summary).to eq("Imported 4 transactions into Checking (0 duplicates skipped)")
  end

  it "Plaid sync writes no audit events" do
    item = create(:plaid_item, access_token: "access-1")
    create(:account, :plaid, plaid_item: item, plaid_account_id: "acc-1")
    plaid_gateway.add_page("access-1", added: [ FakePlaidGateway.plaid_txn("t1", account_id: "acc-1", amount: 1.0, date: Date.new(2026, 10, 1), name: "X") ])
    expect { PlaidSyncJob.perform_now(item) }.not_to change(AuditEvent, :count)
  end
end
```

```ruby
# spec/requests/audit_actors_spec.rb
require "rails_helper"

RSpec.describe "Audit actors" do
  it "attributes setup to the new owner" do
    post setup_path, params: { setup: { household_name: "Home", name: "Alex", email_address: "alex@example.com",
                                        password: AuthHelpers::PASSWORD, password_confirmation: AuthHelpers::PASSWORD } }
    owner = User.find_by!(email_address: "alex@example.com")
    expect(AuditEvent.where(user: owner).pluck(:auditable_type)).to include("Household", "Person")
  end

  it "attributes an invite accepted at sign-up to the new user" do
    business = create(:business)
    invite = create(:invite, business: business, role: "viewer")
    post join_path(token: invite.token), params: { user: { name: "Avery", email_address: "avery@example.com",
                                                           password: AuthHelpers::PASSWORD, password_confirmation: AuthHelpers::PASSWORD } }
    avery = User.find_by!(email_address: "avery@example.com")
    expect(AuditEvent.find_by!(auditable_type: "Membership")).to have_attributes(user_id: avery.id, action: "create")
  end

  it "writes one summary when an editor applies rules to the inbox" do
    business = create(:business)
    software = create(:category, business: business)
    create(:rule, business: business, value: "adobe", category: software)
    create_list(:transaction, 2, account: create(:account, business: business), payee: "ADOBE")
    sign_in_as user_with_role("editor", business)
    post apply_business_rules_path(business)
    expect(AuditEvent.pluck(:action, :summary)).to eq([ [ "summary", "Applied rules: 2 transactions categorized" ] ])
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rspec spec/models/audit_call_sites_spec.rb spec/requests/audit_actors_spec.rb`
Expected: FAIL — per-row events instead of summaries; setup and sign-up events missing.

- [ ] **Step 3: Implement**

`app/forms/setup_form.rb` — replace the transaction body:

```ruby
    ApplicationRecord.transaction do
      return already_completed if Household.exists?

      user = User.create!(name:, email_address:, password:, password_confirmation:, household_owner: true)
      Audit.as(user) do
        household = Household.create!(name: household_name)
        household.people.create!(name:, user:)
        household.people.create!(name: spouse_name) if spouse_name.present?
      end
      user
    end
```

`app/controllers/invite_acceptances_controller.rb` — in `create`'s sign-up branch:

```ruby
      ApplicationRecord.transaction do
        @user.save!
        Audit.as(@user) { @invite.accept!(@user) }
      end
```

`app/services/business_provisioner.rb`:

```ruby
class BusinessProvisioner
  def self.call(business, owner:)
    Audit.summarize do |summary|
      ApplicationRecord.transaction do
        business.save!
        business.memberships.create!(user: owner, role: "owner")
        business.accounts.create!(name: "Cash", source: "manual", kind: "cash")
        CategoryTemplate.apply_to(business)
      end
      summary.record = summary.business = business
      summary.text = "Created book #{business.name}"
    end
    business
  end
end
```

`app/services/personal_book_provisioner.rb` — replace `self.call`:

```ruby
  def self.call(household)
    Audit.summarize do |summary|
      household.with_lock do
        book = household.personal_book || household.businesses.create!(kind: "personal", name: NAME).tap do
          CategoryTemplate.apply_to(_1)
          summary.text = "Created the personal book"
        end
        summary.record = summary.business = book
        sync_memberships(book)
        book
      end
    end
  end
```

`app/controllers/rules_controller.rb#apply`:

```ruby
  def apply
    count = Audit.summarize(business: @business) do |summary|
      RuleApplier.new(@business).apply(@business.transactions.inbox.to_a).tap do
        summary.text = "Applied rules: #{_1} #{"transaction".pluralize(_1)} categorized"
      end
    end
    redirect_to business_inbox_path(@business), notice: "#{count} #{"transaction".pluralize(count)} categorized.", status: :see_other
  end
```

`app/models/csv_import.rb#commit!` — wrap the existing `with_lock` block:

```ruby
  def commit!
    Audit.summarize(record: account) do |summary|
      with_lock do
        # ... existing body unchanged ...
      end
      summary.text = "Imported #{new_count} #{"transaction".pluralize(new_count)} into #{account.name} (#{duplicate_count} duplicates skipped)"
    end
  end
```

`app/models/rule.rb#move_to!` and `app/models/goal.rb#move_to!` — wrap the transaction:

```ruby
  def move_to!(new_position)
    Audit.summarize(record: self) do |summary|
      ApplicationRecord.transaction do
        # ... existing body unchanged ...
      end
      summary.text = "Reordered rules"   # "Reordered goals" in goal.rb
    end
    reload
  end
```

- [ ] **Step 4: Run to verify they pass, then the related suites**

Run: `bundle exec rspec spec/models/audit_call_sites_spec.rb spec/requests/audit_actors_spec.rb spec/requests/setup_spec.rb spec/requests/invites_spec.rb spec/services spec/models/csv_import_spec.rb spec/requests/rules_spec.rb spec/requests/goals_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app spec/models/audit_call_sites_spec.rb spec/requests/audit_actors_spec.rb
git commit -m "Audit setup and sign-up actors; summarize book creation, rule apply, CSV commit and reorders"
```

---

### Task 4: Audit log page

**Files:**
- Create: `app/controllers/audit_events_controller.rb`, `app/helpers/audit_events_helper.rb`, `app/views/audit_events/index.html.erb`
- Modify: `config/routes.rb`, `app/helpers/navigation_helper.rb`
- Test: `spec/requests/audit_events_spec.rb`, `spec/helpers/audit_events_helper_spec.rb`

**Interfaces:**
- Consumes: `AuditEvent.filtered`, `Audit::MODELS`, `DateRangeParams#date_range`.
- Produces: `audit_events_path` (`GET /audit`).

- [ ] **Step 1: Write the failing specs**

```ruby
# spec/requests/audit_events_spec.rb
require "rails_helper"

RSpec.describe "Audit log" do
  let!(:business) { create(:business, name: "Smith Photography") }
  let!(:owner) { create(:user, :household_owner, name: "Alex") }
  let!(:editor) { user_with_role("editor", business, name: "Whitney") }

  it "is forbidden to everyone but the household owner" do
    sign_in_as editor
    get audit_events_path
    expect(response).to have_http_status(:forbidden)
  end

  it "lists events newest first with who, what and the change" do
    rule = Audit.as(editor) { create(:rule, business: business, value: "stripe") }
    Audit.as(owner) { rule.update!(value: "square") }
    sign_in_as owner
    get audit_events_path
    expect(response.body).to match(/Alex.*updated.*Whitney.*created/m)
    expect(response.body).to include("Smith Photography", "stripe", "square")
  end

  it "filters by user and record type, and links a label to its history" do
    Audit.as(editor) { create(:rule, business: business) }
    Audit.as(owner) { create(:client, business: business, name: "Acme") }
    sign_in_as owner
    get audit_events_path(user_id: owner.id)
    expect(response.body).to include("Acme")
    expect(response.body).not_to include("Rule: payee")
    get audit_events_path(auditable_type: "Rule")
    expect(response.body).to include("Rule: payee")
    expect(response.body).to include(audit_events_path(auditable_type: "Rule", auditable_id: Rule.last.id))
  end

  it "pages 50 at a time" do
    Audit.as(owner) { 51.times { |i| Audit.note("Event #{i}") } }
    sign_in_as owner
    get audit_events_path
    expect(response.body).to include("Event 50", "Event 1")
    expect(response.body).not_to include("Event 0<")
    older = AuditEvent.order(:id).second.id
    expect(response.body).to include(audit_events_path(before: older))
    get audit_events_path(before: older)
    expect(response.body).to include("Event 0")
  end
end
```

```ruby
# spec/helpers/audit_events_helper_spec.rb
require "rails_helper"

RSpec.describe AuditEventsHelper do
  it "formats money, booleans, blanks, lists and filtered values" do
    expect(helper.audit_value("amount_cents", -1250)).to eq(Money.new(-1250).to_s)
    expect(helper.audit_value("transfer", true)).to eq("Yes")
    expect(helper.audit_value("transfer", false)).to eq("No")
    expect(helper.audit_value("memo", nil)).to eq("—")
    expect(helper.audit_value("grants", [ "A: viewer", "B: editor" ])).to eq("A: viewer, B: editor")
    expect(helper.audit_value("token_digest", "[FILTERED]")).to eq("[FILTERED]")
  end

  it "describes the action" do
    expect(helper.audit_action(AuditEvent.new(action: "destroy"))).to eq("deleted")
    expect(helper.audit_action(AuditEvent.new(action: "summary", summary: "Reordered rules"))).to eq("Reordered rules")
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rspec spec/requests/audit_events_spec.rb spec/helpers/audit_events_helper_spec.rb`
Expected: FAIL — no route / helper.

- [ ] **Step 3: Implement**

`config/routes.rb`, after `resource :household`:

```ruby
  get "audit", to: "audit_events#index", as: :audit_events
```

```ruby
# app/controllers/audit_events_controller.rb
class AuditEventsController < ApplicationController
  include DateRangeParams

  PER_PAGE = 50

  before_action :require_household_owner!

  def index
    scope = AuditEvent.filtered(**filters, range: date_range)
    @events = page(scope)
    @users = User.order(:name)
    @books = Business.order(:name)
  end

  private

  def filters
    { user_id: params[:user_id].presence, auditable_type: params[:auditable_type].presence_in(Audit::MODELS),
      auditable_id: params[:auditable_id].presence, business_id: params[:business_id].presence }
  end

  # Keyset paging on id, which grows with created_at because events are append-only.
  def page(scope)
    rows = if params[:after].present?
      scope.where("audit_events.id > ?", params[:after].to_i).order(id: :asc).limit(PER_PAGE).to_a.reverse
    else
      newest = scope.order(id: :desc)
      newest = newest.where("audit_events.id < ?", params[:before].to_i) if params[:before].present?
      newest.limit(PER_PAGE).to_a
    end
    @older_id = rows.last.id if rows.any? && scope.where("audit_events.id < ?", rows.last.id).exists?
    @newer_id = rows.first.id if rows.any? && scope.where("audit_events.id > ?", rows.first.id).exists?
    AuditEvent.where(id: rows.map(&:id)).includes(:user, :business).order(id: :desc).to_a
  end
end
```

```ruby
# app/helpers/audit_events_helper.rb
module AuditEventsHelper
  VERBS = { "create" => "created", "update" => "updated", "destroy" => "deleted" }.freeze

  def audit_action(event) = event.summary.presence || VERBS.fetch(event.action)

  def audit_value(name, value)
    return "—" if value.nil?
    return value if value == Audit::FILTERED
    return Money.new(value).to_s if name.to_s.end_with?("_cents") && value.is_a?(Integer)
    return value ? "Yes" : "No" if value == true || value == false

    value.is_a?(Array) ? value.join(", ") : value.to_s
  end

  def audit_type_options = Audit::MODELS.map { [ _1.constantize.model_name.human, _1 ] }.sort

  def audit_page_path(**cursor) = audit_events_path(request.query_parameters.except("before", "after").merge(cursor))
end
```

```erb
<%# app/views/audit_events/index.html.erb %>
<header class="page-header">
  <h1>Audit log</h1>
</header>
<%= form_with url: audit_events_path, method: :get, class: "filters no-print",
              data: { controller: "auto-submit", action: "change->auto-submit#submit" } do |f| %>
  <%= f.select :user_id, options_from_collection_for_select(@users, :id, :name, params[:user_id]), include_blank: "All users" %>
  <%= f.select :auditable_type, options_for_select(audit_type_options, params[:auditable_type]), include_blank: "All records" %>
  <%= f.select :business_id, options_from_collection_for_select(@books, :id, :name, params[:business_id]), include_blank: "All books" %>
  <%= f.hidden_field :auditable_id, value: params[:auditable_id] if params[:auditable_id].present? %>
  <%= f.date_field :from, value: date_range.first %>
  <%= f.date_field :to, value: date_range.last %>
  <noscript><%= f.submit "Filter" %></noscript>
<% end %>
<% if @events.empty? %>
  <p>No changes match these filters.</p>
<% else %>
  <table>
    <thead><tr><th>When</th><th>Who</th><th>What</th><th>Record</th><th>Book</th><th>Changes</th></tr></thead>
    <tbody>
      <% @events.each do |event| %>
        <tr>
          <td><%= l(event.created_at, format: :short) %></td>
          <td><%= event.user.name %></td>
          <td><%= audit_action(event) %></td>
          <td>
            <% if event.auditable_id %>
              <%= link_to event.label, audit_events_path(auditable_type: event.auditable_type, auditable_id: event.auditable_id) %>
            <% else %>
              <%= event.label %>
            <% end %>
          </td>
          <td><%= event.business&.name %></td>
          <td>
            <% if event.changed_values.any? %>
              <details>
                <summary><%= pluralize(event.changed_values.size, "field") %></summary>
                <table>
                  <% event.changed_values.each do |name, (before, after)| %>
                    <tr><th><%= name.humanize %></th><td><%= audit_value(name, before) %></td><td>→</td><td><%= audit_value(name, after) %></td></tr>
                  <% end %>
                </table>
              </details>
            <% end %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <nav class="button-group no-print">
    <%= link_to "Newer", audit_page_path(after: @newer_id), class: "button" if @newer_id %>
    <%= link_to "Older", audit_page_path(before: @older_id), class: "button" if @older_id %>
  </nav>
<% end %>
```

`app/helpers/navigation_helper.rb#settings_links` — add after the People line:

```ruby
      (nav_link "Audit log", audit_events_path if user.household_owner?)
```

- [ ] **Step 4: Run to verify they pass**

Run: `bundle exec rspec spec/requests/audit_events_spec.rb spec/helpers/audit_events_helper_spec.rb spec/requests/navigation_spec.rb`
Expected: PASS. If `navigation_spec` asserts the exact settings list, add "Audit log" to its expectation.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/audit_events_controller.rb app/helpers app/views/audit_events spec/requests/audit_events_spec.rb spec/helpers/audit_events_helper_spec.rb spec/requests/navigation_spec.rb
git commit -m "Audit log page: filters, keyset paging, before/after details"
```

---

### Task 5: Session activity and device labels

**Files:**
- Create: `db/migrate/20261015000002_add_last_seen_at_to_sessions.rb`, `app/models/user_agent_label.rb`
- Modify: `app/models/session.rb`, `app/controllers/concerns/authentication.rb`
- Test: `spec/models/user_agent_label_spec.rb`, `spec/models/session_spec.rb`, `spec/requests/authentication_spec.rb`

**Interfaces:**
- Produces: `Session::TOUCH_INTERVAL`, `Session#seen!`, `Session#device_label`, `UserAgentLabel.call(user_agent) -> String`.

- [ ] **Step 1: Migration**

```ruby
# db/migrate/20261015000002_add_last_seen_at_to_sessions.rb
class AddLastSeenAtToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :last_seen_at, :datetime
    up_only { execute "UPDATE sessions SET last_seen_at = updated_at" }
  end
end
```

Run: `bin/rails db:migrate`.

- [ ] **Step 2: Write the failing specs**

```ruby
# spec/models/user_agent_label_spec.rb
require "rails_helper"

RSpec.describe UserAgentLabel do
  {
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1" => "Safari on iOS",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15" => "Safari on macOS",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36" => "Chrome on Windows",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36 Edg/129.0.0.0" => "Edge on Windows",
    "Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0" => "Firefox on Linux",
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36" => "Chrome on Android",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/129.0 Mobile/15E148 Safari/604.1" => "Chrome on iOS",
    "curl/8.7.1" => "Unknown browser on unknown OS"
  }.each do |agent, label|
    it("labels #{label}") { expect(described_class.call(agent)).to eq(label) }
  end

  it("labels a blank agent") { expect(described_class.call(nil)).to eq("Unknown device") }
end
```

```ruby
# spec/models/session_spec.rb
require "rails_helper"

RSpec.describe Session do
  let(:session) { create(:user).sessions.create! }

  it "starts with last_seen_at set" do
    expect(session.last_seen_at).to be_within(1.second).of(Time.current)
  end

  it "refreshes last_seen_at at most every five minutes without touching updated_at" do
    seen = session.last_seen_at
    travel 4.minutes do
      session.seen!
      expect(session.reload.last_seen_at).to eq(seen)
    end
    travel 6.minutes do
      expect { session.seen! }.not_to(change { session.reload.updated_at })
      expect(session.reload.last_seen_at).to be > seen
    end
  end
end
```

Append to `spec/requests/authentication_spec.rb` (inside the describe):

```ruby
  it "refreshes the session's last_seen_at on requests" do
    sign_in_as user
    record = user.sessions.last
    travel 10.minutes do
      get root_path
      expect(record.reload.last_seen_at).to be_within(1.second).of(Time.current)
    end
  end
```

- [ ] **Step 3: Run to verify they fail**

Run: `bundle exec rspec spec/models/user_agent_label_spec.rb spec/models/session_spec.rb spec/requests/authentication_spec.rb`
Expected: FAIL.

- [ ] **Step 4: Implement**

```ruby
# app/models/user_agent_label.rb
# "Safari on iOS" from a User-Agent header. Order matters: Edge and Chrome on iOS also claim Chrome/Safari, iOS claims Mac OS X.
class UserAgentLabel
  BROWSERS = [ [ /Edg\//, "Edge" ], [ /OPR\//, "Opera" ], [ /Firefox\/|FxiOS\//, "Firefox" ], [ /Chrome\/|CriOS\//, "Chrome" ], [ /Safari\//, "Safari" ] ].freeze
  SYSTEMS = [ [ /iPhone|iPad|iPod/, "iOS" ], [ /Android/, "Android" ], [ /Mac OS X|Macintosh/, "macOS" ], [ /Windows/, "Windows" ], [ /CrOS/, "ChromeOS" ], [ /Linux/, "Linux" ] ].freeze

  def self.call(user_agent)
    return "Unknown device" if user_agent.blank?

    "#{match(BROWSERS, user_agent) || "Unknown browser"} on #{match(SYSTEMS, user_agent) || "unknown OS"}"
  end

  def self.match(table, user_agent) = table.find { |pattern, _| pattern.match?(user_agent) }&.last

  private_class_method :match
end
```

```ruby
# app/models/session.rb
class Session < ApplicationRecord
  TOUCH_INTERVAL = 5.minutes

  belongs_to :user

  before_create { self.last_seen_at ||= Time.current }

  def seen!
    update_column(:last_seen_at, Time.current) if last_seen_at.nil? || last_seen_at < TOUCH_INTERVAL.ago
  end

  def device_label = UserAgentLabel.call(user_agent)
end
```

`app/controllers/concerns/authentication.rb#resume_session`:

```ruby
    def resume_session
      Current.session ||= find_session_by_cookie&.tap(&:seen!)
    end
```

- [ ] **Step 5: Run to verify they pass**

Run: `bundle exec rspec spec/models/user_agent_label_spec.rb spec/models/session_spec.rb spec/requests/authentication_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20261015000002_add_last_seen_at_to_sessions.rb db/schema.rb app/models/session.rb app/models/user_agent_label.rb app/controllers/concerns/authentication.rb spec/models/user_agent_label_spec.rb spec/models/session_spec.rb spec/requests/authentication_spec.rb
git commit -m "Sessions track last_seen_at (throttled) and label their device"
```

---

### Task 6: Sessions page

**Files:**
- Create: `app/controllers/sessions_list_controller.rb`, `app/views/sessions_list/index.html.erb`
- Modify: `config/routes.rb`, `app/views/layouts/_sidebar.html.erb`
- Test: `spec/requests/sessions_list_spec.rb`

**Interfaces:**
- Consumes: `Session#device_label`, `Authentication#terminate_session`.
- Produces: `session_records_path` (`GET /sessions`), `session_record_path(id)` (`DELETE`), `others_session_records_path` (`DELETE /sessions/others`).

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/requests/sessions_list_spec.rb
require "rails_helper"

RSpec.describe "Sessions list" do
  before { create(:household) }

  let(:user) { create(:user) }
  let!(:phone) do
    user.sessions.create!(user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Version/18.0 Mobile Safari/604.1", ip_address: "10.0.0.9")
  end

  it "lists the user's sessions with the current one marked" do
    sign_in_as user
    get session_records_path
    expect(response.body).to include("Safari on iOS", "10.0.0.9", "This device")
  end

  it "revokes another session" do
    sign_in_as user
    delete session_record_path(phone)
    expect(Session.exists?(phone.id)).to be(false)
    expect(response).to redirect_to(session_records_path)
  end

  it "treats revoking the current session as signing out" do
    sign_in_as user
    delete session_record_path(user.sessions.where.not(id: phone.id).last)
    expect(response).to redirect_to(new_session_path)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "revokes every other session" do
    sign_in_as user
    delete others_session_records_path
    expect(user.sessions.count).to eq(1)
    expect(Session.exists?(phone.id)).to be(false)
  end

  it "returns 404 for someone else's session" do
    sign_in_as create(:user)
    delete session_record_path(phone)
    expect(response).to have_http_status(:not_found)
    expect(Session.exists?(phone.id)).to be(true)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/sessions_list_spec.rb` — Expected: FAIL (no route).

- [ ] **Step 3: Implement**

`config/routes.rb`, after `resource :session, ...`:

```ruby
  resources :sessions, only: %i[index destroy], controller: "sessions_list", as: :session_records do
    delete :others, on: :collection
  end
```

```ruby
# app/controllers/sessions_list_controller.rb
# A user's own sessions. Sign-in and sign-out stay in SessionsController.
class SessionsListController < ApplicationController
  def index
    @sessions = Current.user.sessions.order(last_seen_at: :desc)
  end

  def destroy
    record = Current.user.sessions.find(params[:id])
    if record == Current.session
      terminate_session
      return redirect_to(new_session_path, status: :see_other)
    end

    record.destroy!
    redirect_to session_records_path, notice: "Session revoked.", status: :see_other
  end

  def others
    Current.user.sessions.where.not(id: Current.session.id).destroy_all
    redirect_to session_records_path, notice: "Signed out of every other session.", status: :see_other
  end
end
```

```erb
<%# app/views/sessions_list/index.html.erb %>
<header class="page-header">
  <h1>Sessions</h1>
  <% if @sessions.size > 1 %>
    <%= confirm_button "Sign out everywhere else", others_session_records_path, method: :delete,
                       confirm: "Sign out of every other device?", class: "button" %>
  <% end %>
</header>
<table>
  <thead><tr><th>Device</th><th>IP address</th><th>Signed in</th><th>Last seen</th><th></th></tr></thead>
  <tbody>
    <% @sessions.each do |record| %>
      <tr>
        <td><%= record.device_label %> <%= tag.span("This device", class: "badge badge-pos") if record == Current.session %></td>
        <td><%= record.ip_address %></td>
        <td><%= l(record.created_at, format: :short) %></td>
        <td><%= record.last_seen_at ? "#{time_ago_in_words(record.last_seen_at)} ago" : "—" %></td>
        <td>
          <% unless record == Current.session %>
            <div class="button-group"><%= confirm_button "Revoke", session_record_path(record), method: :delete, confirm: "Sign out this device?" %></div>
          <% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

`app/views/layouts/_sidebar.html.erb` — in `.sidebar-footer`, after the `sidebar-user` span:

```erb
    <%= link_to "Sessions", session_records_path, class: "ghost" %>
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/requests/sessions_list_spec.rb spec/requests/navigation_spec.rb spec/system/sidebar_drawer_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/sessions_list_controller.rb app/views/sessions_list app/views/layouts/_sidebar.html.erb spec/requests/sessions_list_spec.rb
git commit -m "Sessions page: list, revoke one, sign out everywhere else"
```

---

### Task 7: Deactivated users can't sign in

**Files:**
- Create: `db/migrate/20261015000003_add_deactivated_at_to_users.rb`, `app/models/user/deactivation.rb`
- Modify: `app/models/user.rb`, `app/controllers/sessions_controller.rb`, `app/controllers/concerns/authentication.rb`
- Test: `spec/models/user/deactivation_spec.rb`, `spec/requests/authentication_spec.rb`

**Interfaces:**
- Produces: `User.active`, `User.deactivated`, `User#deactivated?`; `User::Deactivation.call(user, by:) -> Result` with `#ok?` and `#error`.

- [ ] **Step 1: Migration**

```ruby
# db/migrate/20261015000003_add_deactivated_at_to_users.rb
class AddDeactivatedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deactivated_at, :datetime
  end
end
```

Run: `bin/rails db:migrate`.

- [ ] **Step 2: Write the failing specs**

```ruby
# spec/models/user/deactivation_spec.rb
require "rails_helper"

RSpec.describe User::Deactivation do
  let!(:business) { create(:business, name: "Smith Photography") }
  let!(:owner) { user_with_role("owner", business, household_owner: true, name: "Alex") }
  let!(:accountant) { user_with_role("viewer", business, name: "Avery") }

  def deactivate(user, by: owner) = Audit.as(by) { described_class.call(user, by:) }

  it "removes memberships, ends sessions, revokes their invites and deactivates" do
    accountant.sessions.create!
    accountant.memberships.find_by(business:).update!(role: "owner")
    other_owner = user_with_role("owner", business)
    invite = Invite.create!(created_by: accountant, grant_roles: { business.id => "viewer" })
    result = deactivate(accountant)
    expect(result).to be_ok
    expect(accountant.reload).to be_deactivated
    expect(accountant.memberships).to be_empty
    expect(accountant.sessions).to be_empty
    expect(Invite.find_usable(invite.token)).to be_nil
    expect(other_owner.membership_for(business)).to be_owner
    expect(AuditEvent.where(action: "summary").pluck(:summary)).to eq([ "Removed Avery from the household" ])
    expect(AuditEvent.where(auditable_type: "Membership", action: "destroy").count).to eq(1)
  end

  it "refuses yourself, household owners, and the last owner of a book" do
    expect(deactivate(owner).error).to eq("You can't remove yourself.")
    expect(deactivate(create(:user, :household_owner), by: owner).error).to eq("Household owners can't be removed.")
    accountant.memberships.find_by(business:).update!(role: "owner")
    owner.memberships.find_by(business:).update!(role: "editor")
    expect(deactivate(accountant).error).to eq("Avery is the last owner of Smith Photography. Make someone else an owner first.")
    expect(accountant.reload).not_to be_deactivated
    expect(accountant.memberships).not_to be_empty
  end
end
```

Append to `spec/requests/authentication_spec.rb`:

```ruby
  it "refuses a deactivated user's correct password with the usual message" do
    user.update!(deactivated_at: Time.current)
    log_in_password
    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq("Try another email address or password.")
  end

  it "signs out a deactivated user's live session on the next request" do
    sign_in_as user
    user.update!(deactivated_at: Time.current)
    get root_path
    expect(response).to redirect_to(new_session_path)
    expect(user.sessions.count).to eq(0)
  end

  it "refuses a deactivated user at the 2FA step" do
    log_in_password
    user.update!(deactivated_at: Time.current)
    post two_factor_path, params: { code: user.totp.now }
    expect(response).to redirect_to(new_session_path)
    expect(user.sessions.count).to eq(0)
  end
```

- [ ] **Step 3: Run to verify they fail**

Run: `bundle exec rspec spec/models/user/deactivation_spec.rb spec/requests/authentication_spec.rb`
Expected: FAIL.

- [ ] **Step 4: Implement**

`app/models/user.rb` — add:

```ruby
  scope :active, -> { where(deactivated_at: nil) }
  scope :deactivated, -> { where.not(deactivated_at: nil) }

  def deactivated? = deactivated_at.present?
```

`app/controllers/sessions_controller.rb#create`:

```ruby
    user = User.authenticate_by(params.permit(:email_address, :password))
    if user && !user.deactivated?
      begin_two_factor(user)
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
```

`app/controllers/concerns/authentication.rb`:

```ruby
    def find_session_by_cookie
      record = Session.includes(:user).find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
      return record unless record && (record.created_at < SESSION_TTL.ago || record.user.deactivated?)

      record.destroy
      cookies.delete(:session_id)
      nil
    end
```

and in `pending_user`, change `User.find_by(id: session[:pending_user_id])` to `User.active.find_by(id: session[:pending_user_id])`.

```ruby
# app/models/user/deactivation.rb
# "Remove from household": drops every membership, ends every session, revokes invites they created, and blocks sign-in.
# The user row stays so audit events keep their actor.
class User::Deactivation
  Result = Data.define(:error) do
    def ok? = error.nil?
  end

  def self.call(user, by:) = new(user, by).call

  def initialize(user, actor)
    @user = user
    @actor = actor
  end

  def call
    ApplicationRecord.transaction do
      Business.where(id: @user.memberships.select(:business_id)).order(:id).each(&:lock!)
      error = refusal
      next Result.new(error:) if error

      @user.memberships.each(&:destroy!)
      @user.sessions.destroy_all
      Invite.usable.where(created_by: @user).find_each { _1.update!(expires_at: Time.current) }
      @user.update!(deactivated_at: Time.current)
      Audit.note("Removed #{@user.name} from the household", record: @user)
      Result.new(error: nil)
    end
  end

  private

  def refusal
    return "You can't remove yourself." if @user == @actor
    return "Household owners can't be removed." if @user.household_owner?

    books = @user.memberships.owner.includes(:business).select(&:last_owner?).map(&:business)
    "#{@user.name} is the last owner of #{books.map(&:name).to_sentence}. Make someone else an owner first." if books.any?
  end
end
```

- [ ] **Step 5: Run to verify they pass**

Run: `bundle exec rspec spec/models/user/deactivation_spec.rb spec/requests/authentication_spec.rb spec/requests/invites_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20261015000003_add_deactivated_at_to_users.rb db/schema.rb app/models/user.rb app/models/user/deactivation.rb app/controllers/sessions_controller.rb app/controllers/concerns/authentication.rb spec/models/user/deactivation_spec.rb spec/requests/authentication_spec.rb
git commit -m "Deactivated users can't sign in; User::Deactivation removes access"
```

---

### Task 8: Users page

**Files:**
- Create: `app/controllers/users_controller.rb`, `app/views/users/index.html.erb`
- Modify: `config/routes.rb`, `app/helpers/navigation_helper.rb`
- Test: `spec/requests/users_spec.rb`

**Interfaces:**
- Consumes: `User::Deactivation.call`, `User.active`, `User.deactivated`, `Audit.note`.
- Produces: `users_path`, `sign_out_user_path(user)`, `deactivate_user_path(user)`, `reactivate_user_path(user)`.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/requests/users_spec.rb
require "rails_helper"

RSpec.describe "Users" do
  let!(:business) { create(:business, name: "Smith Photography") }
  let!(:owner) { user_with_role("owner", business, household_owner: true, name: "Alex") }
  let!(:accountant) { user_with_role("viewer", business, name: "Avery") }

  it "is forbidden to everyone but the household owner" do
    sign_in_as accountant
    get users_path
    expect(response).to have_http_status(:forbidden)
    patch deactivate_user_path(owner)
    expect(response).to have_http_status(:forbidden)
  end

  it "lists users with their books and roles" do
    sign_in_as owner
    get users_path
    expect(response.body).to include("Avery", "Smith Photography", "Viewer", "Household owner")
  end

  it "signs a user out everywhere" do
    accountant.sessions.create!
    sign_in_as owner
    patch sign_out_user_path(accountant)
    expect(accountant.sessions.count).to eq(0)
    expect(response).to redirect_to(users_path)
  end

  it "removes and reactivates a user" do
    sign_in_as owner
    patch deactivate_user_path(accountant)
    expect(flash[:notice]).to eq("Avery removed from the household.")
    expect(accountant.reload).to be_deactivated
    get users_path
    expect(response.body).to include("Removed")
    patch reactivate_user_path(accountant)
    expect(accountant.reload).not_to be_deactivated
    expect(AuditEvent.where(action: "summary").pluck(:summary)).to eq([ "Removed Avery from the household", "Reactivated Avery" ])
  end

  it "explains a refusal" do
    sign_in_as owner
    patch deactivate_user_path(owner)
    expect(flash[:alert]).to eq("You can't remove yourself.")
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/users_spec.rb` — Expected: FAIL.

- [ ] **Step 3: Implement**

`config/routes.rb`:

```ruby
  resources :users, only: :index do
    member do
      patch :sign_out
      patch :deactivate
      patch :reactivate
    end
  end
```

```ruby
# app/controllers/users_controller.rb
# Household-owner view of every login: book access, last activity, sign-out and removal. Taxpayers live on PeopleController.
class UsersController < ApplicationController
  before_action :require_household_owner!
  before_action :set_user, except: :index

  def index
    @users = User.active.includes(memberships: :business).order(:name)
    @deactivated = User.deactivated.order(:name)
    @last_seen = Session.group(:user_id).maximum(:last_seen_at)
  end

  def sign_out
    @user.sessions.destroy_all
    if @user == Current.user
      cookies.delete(:session_id)
      return redirect_to(new_session_path, status: :see_other)
    end

    redirect_to users_path, notice: "Signed #{@user.name} out everywhere.", status: :see_other
  end

  def deactivate
    result = User::Deactivation.call(@user, by: Current.user)
    if result.ok?
      redirect_to users_path, notice: "#{@user.name} removed from the household.", status: :see_other
    else
      redirect_to users_path, alert: result.error, status: :see_other
    end
  end

  def reactivate
    @user.update!(deactivated_at: nil)
    Audit.note("Reactivated #{@user.name}", record: @user)
    redirect_to users_path, notice: "#{@user.name} reactivated. Send an invite to give them access to books.", status: :see_other
  end

  private

  def set_user
    @user = User.find(params[:id])
  end
end
```

```erb
<%# app/views/users/index.html.erb %>
<header class="page-header">
  <h1>Users</h1>
  <%= primary_action "Invite someone", new_invite_path %>
</header>
<table>
  <thead><tr><th>Name</th><th>Books</th><th>Last seen</th><th></th></tr></thead>
  <tbody>
    <% @users.each do |user| %>
      <tr>
        <td>
          <%= user.name %> <%= tag.span("Household owner", class: "badge") if user.household_owner? %><br>
          <small><%= user.email_address %></small>
        </td>
        <td><%= user.memberships.map { "#{_1.business.name}: #{_1.role.humanize}" }.sort.join(", ").presence || "—" %></td>
        <td><%= (seen = @last_seen[user.id]) ? "#{time_ago_in_words(seen)} ago" : "Never" %></td>
        <td>
          <div class="button-group">
            <%= confirm_button "Sign out everywhere", sign_out_user_path(user), method: :patch, confirm: "Sign #{user.name} out of every device?" %>
            <% unless user.household_owner? %>
              <%= confirm_button "Remove from household", deactivate_user_path(user), method: :patch,
                                 confirm: "Remove #{user.name}? They lose access to every book and can't sign in." %>
            <% end %>
          </div>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
<% if @deactivated.any? %>
  <h2>Removed</h2>
  <table>
    <thead><tr><th>Name</th><th>Removed</th><th></th></tr></thead>
    <tbody>
      <% @deactivated.each do |user| %>
        <tr>
          <td><%= user.name %><br><small><%= user.email_address %></small></td>
          <td><%= l(user.deactivated_at, format: :short) %></td>
          <td><div class="button-group"><%= confirm_button "Reactivate", reactivate_user_path(user), method: :patch, confirm: "Let #{user.name} sign in again?" %></div></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>
```

`app/helpers/navigation_helper.rb#settings_links` — add after the People line, before Audit log:

```ruby
      (nav_link "Users", users_path if user.household_owner?),
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/requests/users_spec.rb spec/requests/navigation_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/users_controller.rb app/views/users app/helpers/navigation_helper.rb spec/requests/users_spec.rb spec/requests/navigation_spec.rb
git commit -m "Users page: sign out everywhere, remove from household, reactivate"
```

---

### Task 9: Error capture

**Files:**
- Create: `db/migrate/20261015000004_create_error_events.rb`, `app/models/error_event.rb`, `app/models/error_log.rb`, `config/initializers/error_log.rb`
- Test: `spec/models/error_log_spec.rb`

**Interfaces:**
- Produces: `ErrorEvent.unresolved`, `ErrorEvent.resolved`, `ErrorEvent.recent_first`; `ErrorLog#report(error, handled:, severity:, context:, source: nil)`.

- [ ] **Step 1: Migration**

```ruby
# db/migrate/20261015000004_create_error_events.rb
class CreateErrorEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :error_events do |t|
      t.string :fingerprint, null: false, index: { unique: true }
      t.string :error_class, null: false
      t.text :message, null: false
      t.text :backtrace, null: false
      t.string :source
      t.integer :occurrences, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.integer :last_user_id
      t.datetime :resolved_at
      t.timestamps
    end
  end
end
```

Run: `bin/rails db:migrate`.

- [ ] **Step 2: Write the failing spec**

```ruby
# spec/models/error_log_spec.rb
require "rails_helper"

RSpec.describe ErrorLog do
  def raised(error_class = RuntimeError, message = "boom")
    raise error_class, message
  rescue error_class => e
    e
  end

  def report(error, context: {}) = described_class.new.report(error, handled: false, severity: :error, context:)

  it "records an unhandled error with its source and actor" do
    controller = InvoicesController.new.tap { _1.action_name = "create" }
    user = create(:user)
    Current.set(audit_actor: user) { report(raised, context: { controller: }) }
    expect(ErrorEvent.last).to have_attributes(error_class: "RuntimeError", message: "boom", source: "InvoicesController#create",
                                               occurrences: 1, last_user_id: user.id)
  end

  it "groups repeats and reopens a resolved error" do
    error = raised
    report(error)
    ErrorEvent.last.update!(resolved_at: Time.current)
    report(error)
    expect(ErrorEvent.count).to eq(1)
    expect(ErrorEvent.last).to have_attributes(occurrences: 2, resolved_at: nil)
  end

  it "truncates long messages" do
    report(raised(RuntimeError, "x" * 5_000))
    expect(ErrorEvent.last.message.length).to eq(1_000)
  end

  it "skips 4xx exceptions and warnings" do
    report(raised(ActiveRecord::RecordNotFound))
    described_class.new.report(raised, handled: true, severity: :warning, context: {})
    expect(ErrorEvent.count).to eq(0)
  end

  it "never raises, even when saving fails" do
    allow(ErrorEvent).to receive(:find_or_initialize_by).and_raise(ActiveRecord::StatementInvalid, "db gone")
    expect(Rails.logger).to receive(:error).with(/ErrorLog failed/)
    expect { report(raised) }.not_to raise_error
  end

  it "is subscribed to Rails.error" do
    expect { Rails.error.report(raised, handled: false, severity: :error) }.to change(ErrorEvent, :count).by(1)
  end
end
```

- [ ] **Step 3: Run to verify it fails**

Run: `bundle exec rspec spec/models/error_log_spec.rb` — Expected: FAIL.

- [ ] **Step 4: Implement**

```ruby
# app/models/error_event.rb
class ErrorEvent < ApplicationRecord
  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :recent_first, -> { order(last_seen_at: :desc) }
end
```

```ruby
# app/models/error_log.rb
# Rails.error subscriber: groups server errors from requests and jobs into ErrorEvents for the owner's Errors page.
# Stores no params, headers or cookies, and never raises.
class ErrorLog
  BACKTRACE_LINES = 30
  MESSAGE_LIMIT = 1_000

  def report(error, handled:, severity:, context:, source: nil)
    return unless severity == :error
    return if ActionDispatch::ExceptionWrapper.status_code_for_exception(error.class.name) < 500

    record(error, context)
  rescue StandardError => e
    Rails.logger.error("ErrorLog failed to record #{error.class}: #{e.class}: #{e.message}")
  end

  private

  def record(error, context)
    now = Time.current
    backtrace = Rails.backtrace_cleaner.clean(error.backtrace || [])
    event = ErrorEvent.find_or_initialize_by(fingerprint: fingerprint(error, backtrace))
    event.assign_attributes(error_class: error.class.name, message: error.message.to_s.truncate(MESSAGE_LIMIT, omission: ""),
                            backtrace: backtrace.first(BACKTRACE_LINES).join("\n"), source: source_for(context),
                            last_seen_at: now, last_user_id: Current.actor&.id, resolved_at: nil)
    event.first_seen_at ||= now
    event.occurrences = event.new_record? ? 1 : event.occurrences + 1
    event.save!
  end

  def fingerprint(error, backtrace)
    Digest::SHA256.hexdigest("#{error.class.name}|#{backtrace.find { _1.start_with?("app/") } || backtrace.first}")
  end

  def source_for(context)
    if (controller = context[:controller])
      "#{controller.class.name}##{controller.action_name}"
    elsif (job = context[:job])
      job.class.name
    end
  end
end
```

```ruby
# config/initializers/error_log.rb
Rails.application.config.after_initialize { Rails.error.subscribe(ErrorLog.new) }
```

- [ ] **Step 5: Run to verify it passes**

Run: `bundle exec rspec spec/models/error_log_spec.rb` — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20261015000004_create_error_events.rb db/schema.rb app/models/error_event.rb app/models/error_log.rb config/initializers/error_log.rb spec/models/error_log_spec.rb
git commit -m "Error log: group unhandled server errors from Rails.error"
```

---

### Task 10: Errors page

**Files:**
- Create: `app/controllers/error_events_controller.rb`, `app/views/error_events/index.html.erb`
- Modify: `config/routes.rb`, `app/helpers/navigation_helper.rb`
- Test: `spec/requests/error_events_spec.rb`

**Interfaces:**
- Produces: `error_events_path(tab:)`, `resolve_error_event_path(event)`, `reopen_error_event_path(event)`.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/requests/error_events_spec.rb
require "rails_helper"

RSpec.describe "Errors" do
  let!(:owner) { create(:user, :household_owner) }
  let!(:event) do
    ErrorEvent.create!(fingerprint: "f", error_class: "RuntimeError", message: "boom", backtrace: "app/models/x.rb:1",
                       source: "InvoicesController#create", occurrences: 3, first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago)
  end

  before { create(:household) }

  it "is forbidden to everyone but the household owner" do
    sign_in_as create(:user)
    get error_events_path
    expect(response).to have_http_status(:forbidden)
  end

  it "lists open errors, shows a sidebar badge, and resolves and reopens them" do
    sign_in_as owner
    get error_events_path
    expect(response.body).to include("RuntimeError", "boom", "InvoicesController#create", "app/models/x.rb:1")
    expect(response.body).to match(%r{Errors <span class="badge">1</span>})
    patch resolve_error_event_path(event)
    expect(event.reload.resolved_at).to be_present
    get error_events_path
    expect(response.body).not_to include("boom")
    get error_events_path(tab: "resolved")
    expect(response.body).to include("boom")
    patch reopen_error_event_path(event, tab: "resolved")
    expect(event.reload.resolved_at).to be_nil
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/error_events_spec.rb` — Expected: FAIL.

- [ ] **Step 3: Implement**

`config/routes.rb`:

```ruby
  resources :error_events, only: :index, path: "errors" do
    member do
      patch :resolve
      patch :reopen
    end
  end
```

```ruby
# app/controllers/error_events_controller.rb
class ErrorEventsController < ApplicationController
  before_action :require_household_owner!

  def index
    @tab = params[:tab] == "resolved" ? "resolved" : "open"
    @error_events = (@tab == "resolved" ? ErrorEvent.resolved : ErrorEvent.unresolved).recent_first.limit(200)
  end

  def resolve = set_resolved(Time.current, "resolved")
  def reopen = set_resolved(nil, "reopened")

  private

  def set_resolved(resolved_at, verb)
    ErrorEvent.find(params[:id]).update!(resolved_at:)
    redirect_to error_events_path(tab: params[:tab]), notice: "Error #{verb}.", status: :see_other
  end
end
```

```erb
<%# app/views/error_events/index.html.erb %>
<header class="page-header">
  <h1>Errors</h1>
</header>
<nav class="button-group no-print">
  <%= link_to "Open", error_events_path, class: "button", aria: { current: ("page" if @tab == "open") } %>
  <%= link_to "Resolved", error_events_path(tab: "resolved"), class: "button", aria: { current: ("page" if @tab == "resolved") } %>
</nav>
<% if @error_events.empty? %>
  <p><%= @tab == "open" ? "No open errors." : "No resolved errors." %></p>
<% else %>
  <table>
    <thead><tr><th>Error</th><th>Where</th><th class="num">Count</th><th>First seen</th><th>Last seen</th><th></th></tr></thead>
    <tbody>
      <% @error_events.each do |event| %>
        <tr>
          <td>
            <details>
              <summary><strong><%= event.error_class %></strong>: <%= event.message %></summary>
              <pre><%= event.backtrace %></pre>
            </details>
          </td>
          <td><%= event.source %></td>
          <td class="num"><%= event.occurrences %></td>
          <td><%= l(event.first_seen_at, format: :short) %></td>
          <td><%= l(event.last_seen_at, format: :short) %></td>
          <td>
            <div class="button-group">
              <% if @tab == "open" %>
                <%= button_to "Resolve", resolve_error_event_path(event), method: :patch %>
              <% else %>
                <%= button_to "Reopen", reopen_error_event_path(event, tab: "resolved"), method: :patch %>
              <% end %>
            </div>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>
```

`app/helpers/navigation_helper.rb#settings_links` — add after Audit log:

```ruby
      (nav_link "Errors", error_events_path, badge: ErrorEvent.unresolved.count if user.household_owner?)
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/requests/error_events_spec.rb spec/requests/navigation_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/error_events_controller.rb app/views/error_events app/helpers/navigation_helper.rb spec/requests/error_events_spec.rb spec/requests/navigation_spec.rb
git commit -m "Errors page with open/resolved tabs and a sidebar badge"
```

---

### Task 11: Docker log rotation

**Files:**
- Modify: `docker-compose.yml`, `README.md` (`## Logs` section)
- Test: `spec/config/docker_compose_spec.rb`

- [ ] **Step 1: Write the failing spec** (append inside the describe)

```ruby
  it "rotates the app's logs" do
    expect(app["logging"]).to eq("driver" => "json-file", "options" => { "max-size" => "10m", "max-file" => "5" })
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/config/docker_compose_spec.rb` — Expected: FAIL.

- [ ] **Step 3: Implement**

In `docker-compose.yml`, under `services.app`, after `restart: unless-stopped`:

```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
```

In `README.md` under `## Logs`, add:

```markdown
Docker keeps at most 50 MB of app logs (five 10 MB files), so `docker compose logs` only shows what's still kept.
Unhandled errors are also recorded on the **Errors** page (household owner only), grouped by error.
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/config/docker_compose_spec.rb` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docker-compose.yml README.md spec/config/docker_compose_spec.rb
git commit -m "Rotate Docker logs at 5 x 10 MB"
```

---

### Task 12: Demo seed, system specs, docs, full CI

**Files:**
- Modify: `lib/demo_seeder.rb`, `docs/superpowers/specs/2026-10-05-goodbooks-design.md`, `docs/roadmap.md`
- Test: `spec/lib/demo_seeder_spec.rb`, `spec/system/sharing_polish_spec.rb`

- [ ] **Step 1: Write the failing specs**

Append to `spec/lib/demo_seeder_spec.rb` (inside the describe; `run` is the file's existing helper):

```ruby
  it "seeds a second session, audit activity and an open error" do
    run
    alex = User.find_by!(email_address: "alex@example.com")
    expect(alex.sessions.map(&:device_label)).to include("Safari on iOS")
    expect(AuditEvent.count).to be >= 12
    expect(AuditEvent.distinct.pluck(:action)).to include("create", "update", "destroy", "summary")
    expect(AuditEvent.distinct.count(:user_id)).to be >= 2
    expect(ErrorEvent.unresolved.count).to eq(1)
  end
```

```ruby
# spec/system/sharing_polish_spec.rb
require "rails_helper"

RSpec.describe "Sharing polish" do
  let!(:business) { create(:business, name: "Smith Photography") }
  let!(:owner) { user_with_role("owner", business, household_owner: true, name: "Alex") }
  let!(:accountant) { user_with_role("viewer", business, name: "Avery") }

  it "revokes another session" do
    accountant.sessions.create!(user_agent: "Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0")
    system_sign_in_as accountant
    click_on "Sessions"
    within("tr", text: "Firefox on Linux") { click_on "Revoke" }
    expect(page).to have_content("Session revoked.")
    expect(page).not_to have_content("Firefox on Linux")
  end

  it "removes a user, who then can't sign in, and shows it in the audit log" do
    system_sign_in_as owner
    click_on "Users"
    within("tr", text: "Avery") { click_on "Remove from household" }
    expect(page).to have_content("Avery removed from the household.")
    click_on "Audit log"
    expect(page).to have_content("Removed Avery from the household")
    visit audit_events_path(user_id: owner.id, auditable_type: "Membership")
    expect(page).to have_content("Avery in Smith Photography (viewer)")
    expect(page).to have_content("deleted")
    click_on "Sign out"
    visit new_session_path
    fill_in "email_address", with: accountant.email_address
    fill_in "password", with: AuthHelpers::PASSWORD
    click_on "Sign in"
    expect(page).to have_content("Try another email address or password.")
  end

  it "resolves an error" do
    ErrorEvent.create!(fingerprint: "f", error_class: "RuntimeError", message: "boom", backtrace: "app/x.rb:1",
                       first_seen_at: 1.hour.ago, last_seen_at: 1.hour.ago)
    system_sign_in_as owner
    click_on "Errors"
    click_on "Resolve"
    expect(page).to have_content("Error resolved.")
    expect(page).to have_content("No open errors.")
  end
end
```

These run under rack_test (no `js: true`), so the confirm dialogs don't block clicks and `<details>` content is always in the page.

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb spec/system/sharing_polish_spec.rb`
Expected: the seeder example FAILs; the system specs PASS or fail only on copy — fix the views, not the expectations.

- [ ] **Step 3: Implement the seeder**

In `lib/demo_seeder.rb#build`, after `seed_goals(household)`:

```ruby
    seed_activity(alex, whitney, sound_roots, gardens)
```

Add the private method:

```ruby
  PHONE_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1".freeze

  # A second login for Alex, a couple of weeks of edits by Alex and Whitney, and one open error.
  def seed_activity(owner, editor, business, book)
    owner.sessions.create!(user_agent: PHONE_AGENT, ip_address: "192.168.1.24", last_seen_at: 1.day.ago)
    Audit.as(editor) do
      book.transactions.order(posted_on: :desc).limit(4).each { _1.update!(memo: "Checked against receipt") }
      book.mileage_entries.order(:driven_on).first&.destroy!
      book.clients.create!(name: "Hollow Oak Florist")
    end
    Audit.as(owner) do
      business.transactions.order(posted_on: :desc).offset(4).limit(4).each { _1.update!(memo: "Receipt in Drive") }
      business.rules.ordered.first&.move_to!(1)
      Invite.create!(created_by: owner, email: "bookkeeper@example.com", grant_roles: { business.id => "viewer" })
    end
    ErrorEvent.create!(fingerprint: "demo", error_class: "Net::ReadTimeout", message: "Demo error: the bank timed out during sync",
                       backtrace: "app/services/plaid_feed/sync.rb:21:in 'PlaidFeed::Sync#call'", source: "PlaidSyncJob",
                       occurrences: 3, first_seen_at: 2.days.ago, last_seen_at: 3.hours.ago)
  end
```

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb` — Expected: PASS (all examples, including the existing ones).

- [ ] **Step 4: Update the docs**

`docs/superpowers/specs/2026-10-05-goodbooks-design.md`:
- Under `## 10. Sub-project 7: Sharing polish`, insert as the first line: `Refined and superseded by \`2026-10-14-goodbooks-sharing-polish-design.md\`. Email delivery was dropped. Removing a user deactivates their login. The audit list was updated to the current models, and an error log was added.`
- In §5.3, replace `- Email delivery arrives in sub-project 7.` with `- Invites are copy-link only; email delivery was dropped (sharing polish spec §1).`
- In §5.10, change `Later sub-projects add \`PLAID_*\` and \`SMTP_*\`.` to `Plaid adds \`PLAID_*\`.`

`docs/roadmap.md`:
- Row 7: Contents → `session management, household user removal (deactivation), audit log, error log, Docker log rotation`; Design → `[own spec](superpowers/specs/2026-10-14-goodbooks-sharing-polish-design.md)`; Size → `12`; Status → `In progress`.
- Documents table row 7: Spec → `[design](superpowers/specs/2026-10-14-goodbooks-sharing-polish-design.md)`, Plan → `[Sharing polish](superpowers/plans/2026-10-15-goodbooks-sharing-polish.md)`.
- In "Sharing polish comes last", replace the sentence `Email delivery and session management need only Core and could ship earlier on their own.` with `Session management needs only Core and could have shipped earlier on its own.`

- [ ] **Step 5: Run every CI check**

```bash
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit
bin/rubocop
bundle exec rspec
```

Expected: all clean / 0 failures. Fix anything that isn't before committing.

- [ ] **Step 6: Commit**

```bash
git add lib/demo_seeder.rb spec/lib/demo_seeder_spec.rb spec/system/sharing_polish_spec.rb docs
git commit -m "Sharing polish: demo activity, system specs, spec and roadmap updates"
```
