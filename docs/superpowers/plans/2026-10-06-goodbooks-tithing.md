# goodbooks Personal Book + Tithing (Sub-project 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the household a "Personal" book for its joint checking account (import, categorize, rules, inbox, spending report) and a weekly tithe ledger (10% of tithable income owed per Sunday–Saturday week, payments applied oldest-week-first, running behind/ahead balance), hidden from the accountant and from every business-only path.

**Architecture:** The personal book is a `Business` row with `kind: "personal"`, so accounts, CSV import, transactions, categories, rules, the inbox, and memberships are reused unchanged. Tithe math lives in a pure `Tithe::Ledger`; `Tithe::Entries` is the only code that knows which transactions are tithable income or tithe payments (category flags `tithable` / `tithe`). Business-only controllers include `BusinessKindOnly` (404 on the personal book); tithe and spending controllers include `PersonalOnly`. Household-wide queries switch from `Business` to `Business.business_kind`.

**Tech Stack:** Ruby 4.0.7, Rails 8.1.4, SQLite, Hotwire, RSpec, FactoryBot, Capybara (rack_test), Brakeman, bundler-audit, RuboCop (rails-omakase), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-06-goodbooks-tithing-design.md` (parent: `docs/superpowers/specs/2026-10-05-goodbooks-design.md` §3 cross-cutting rules).

## Prerequisites (before Task 1)

- `export PATH="$HOME/.rubies/ruby-4.0.7/bin:$PATH"` before every command (`ruby -v` → `ruby 4.0.7`).
- Branch `tithing` (created from `invoices`; holds the spec commit). The PR's base is `invoices` (stacked on PR #6), not `main`.
- `bundle exec rspec` → `578 examples, 0 failures` with no other output. This is the baseline; if it is not green, stop and report.

## Global Constraints

- Money is signed integer cents in `*_cents` columns; display with `money(cents)`; rounding only through `Money.round_rational`. Never floats.
- `Transaction#amount_cents`: positive = money into the account.
- Tithe rate is the constant `Rational(1, 10)`; owed is rounded once per week.
- Weeks run Sunday–Saturday: `week_start(date) = date - date.wday`.
- Never name an association, method, or local `transaction`. DB transactions use `ApplicationRecord.transaction` (or `with_lock`).
- Non-member → 404 (lookups through `Current.user.accessible_businesses`). Viewer writing → 403 (`require_editor!`). Owner-only → 403 (`require_owner!`). Business-only screens on the personal book → 404 (`BusinessKindOnly`). Household screens → 404 unless `Current.user.can_view_household?`.
- In the UI the personal book is always "Personal", never a business. `Business.business_kind` is the scope for "real businesses"; `Business.personal` for the personal book.
- Strong params never list a `*_id` key.
- `config.action_controller.raise_on_missing_callback_actions = true` in test: every `only:`/`except:` list must name existing actions.
- Test output must stay clean: a passing `bundle exec rspec` prints only the reporter.
- TDD: each task writes its failing spec first and runs it to see it fail.
- Formatting: single spaces in literals, no column alignment. `bin/rubocop` must pass after every task.
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01VdQWdubZ6L19ekyi7gz8GK
  ```
- Kaneo: the controlling session (not task implementers) comments progress on GB-9 ("New sub-project: Household joint account + tithing", project GoodBooks, workspace Root User Projects) after each task and moves it to In Review when the PR opens.

## Review Focus

1. **Positive amounts in expense categories**: a grocery refund (+$25 in Groceries) is not tithable income; a refunded tithe (+$100 in Tithe) reduces paid and is not income. (Pinned in Task 4.)
2. **Week and date boundaries**: Saturday vs. Sunday transactions, a start date mid-week (earlier days in that week ignored), `today` mid-week, and future-dated transactions (ignored). (Pinned in Task 3.)
3. **The accountant probing personal URLs**: book overview, accounts, transactions, inbox, categories, tithe (HTML and CSV), spending (HTML and CSV) → 404; household P&L, transaction export, dashboard, and invites leak nothing personal. (Pinned in Tasks 6, 7, 8.)
4. **Category form flag combinations**: creating a personal expense category with "Tithable" unchecked, or switching a not-tithable income category to expense, saves cleanly (flags normalize); a crafted `tithe: "1"` on a business category is rejected. (Pinned in Tasks 1 and 5.)
5. **Typed tithe start dates**: `abc` → "Tithe start date is not a valid date." with the old value kept; a future date → validation flash; blank → tracking turned off and the prompt shown; never a 500. (Pinned in Task 7.)

## File Map

```
db/migrate/20261008000001_add_personal_book_to_businesses.rb   (Task 1)
db/migrate/20261008000002_add_tithe_flags_to_categories.rb     (Task 1)
app/models/business.rb, household.rb, category.rb, category_template.rb  (Task 1)
spec/factories/businesses.rb, categories.rb                    (Task 1)
app/services/personal_book_provisioner.rb                      (Task 2)
app/controllers/personal_books_controller.rb, people_controller.rb, dashboards view, layout nav, application_helper.rb (Task 2)
app/models/tithe/ledger.rb                                     pure (Task 3)
app/models/tithe/entries.rb, app/models/tithe.rb               (Task 4)
app/controllers/concerns/{business_kind_only,personal_only}.rb (Task 5)
business-only controllers, businesses/_nav, businesses/show, categories views/controller, categories_helper.rb, reports/transaction_csv.rb (Task 5)
app/models/user.rb, household_* controllers, dashboards_controller.rb, invites_controller.rb, invite.rb, household_inboxes_controller.rb (Task 6)
app/controllers/tithes_controller.rb, views/tithes/show.html.erb, helpers/tithes_helper.rb, models/reports/tithe_csv.rb (Task 7)
app/models/reports/{spending,spending_csv}.rb, controllers/spending_reports_controller.rb, views/spending_reports/show.html.erb (Task 8)
lib/demo_seeder.rb                                             (Task 9)
spec/system/personal_tithe_spec.rb, spec/fixtures/files/joint_checking.csv, README.md (Task 10)
```

---

### Task 1: Schema, `Business` kind, category tithe flags, personal template

**Files:**
- Create: `db/migrate/20261008000001_add_personal_book_to_businesses.rb`, `db/migrate/20261008000002_add_tithe_flags_to_categories.rb`, `spec/models/business_spec.rb`
- Modify: `app/models/business.rb`, `app/models/household.rb`, `app/models/category.rb`, `app/models/category_template.rb`, `spec/factories/businesses.rb`, `spec/factories/categories.rb`, `spec/models/category_spec.rb`, `spec/models/household_spec.rb`

**Interfaces:**
- Produces: `Business#personal?`, `Business#business?`, scopes `Business.business_kind`, `Business.personal`; column `businesses.tithe_start_on` (date); `Household#personal_book` (Business or nil); `Category#tithable?`, `Category#tithe?`; `CategoryTemplate::PERSONAL`, `CategoryTemplate.apply_to(business)` (picks the template by kind); factory trait `create(:business, :personal)`; the category factory picks `schedule_c_line` nil for personal books.

- [ ] **Step 1: Write the failing specs**

`spec/models/business_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Business do
  it "defaults to a business that needs a person" do
    business = build(:business, person: nil)
    expect(business).to be_business
    expect(business).not_to be_valid
    expect(business.errors[:person]).to be_present
  end

  it "allows one personal book per household, with no person" do
    book = create(:business, :personal)
    expect(book).to be_personal
    expect(book.person).to be_nil
    expect(Business.personal).to eq([ book ])
    expect(Business.business_kind).not_to include(book)
    expect(build(:business, :personal)).not_to be_valid
  end

  it "rejects a person on the personal book" do
    expect(build(:business, :personal, person: create(:person))).not_to be_valid
  end

  it "accepts a past or today tithe start date only on the personal book" do
    book = create(:business, :personal)
    expect(book.update(tithe_start_on: Date.current)).to be(true)
    expect(book.update(tithe_start_on: Date.current + 1)).to be(false)
    expect(book.errors[:tithe_start_on]).to include("can't be in the future")
    expect(build(:business, tithe_start_on: Date.current - 1)).not_to be_valid
  end

  it "refuses to archive the personal book" do
    book = create(:business, :personal)
    expect(book.update(archived_at: Time.current)).to be(false)
  end
end
```

Append to `spec/models/household_spec.rb` (inside the `describe`):

```ruby
  it "finds its personal book" do
    business = create(:business)
    expect(business.household.personal_book).to be_nil
    book = create(:business, :personal)
    expect(business.household.reload.personal_book).to eq(book)
  end
```

Append to `spec/models/category_spec.rb` (inside the top-level `describe`):

```ruby
  describe "personal categories" do
    let(:book) { create(:business, :personal) }

    it "has no Schedule C line" do
      expect(build(:category, business: book)).to be_valid
      expect(build(:category, business: book, schedule_c_line: "18")).not_to be_valid
    end

    it "can be not tithable (income) or a tithe payment (expense)" do
      expect(create(:category, :income, business: book, tithable: false)).not_to be_tithable
      expect(create(:category, business: book, tithe: true)).to be_tithe
    end

    it "normalizes flags that don't apply to the kind" do
      expense = create(:category, business: book, tithable: false)
      expect(expense).to be_tithable
      income = create(:category, :income, business: book, tithe: true)
      expect(income).not_to be_tithe
    end
  end

  it "rejects tithe flags on business categories" do
    expect(build(:category, tithe: true)).not_to be_valid
    expect(build(:category, :income, tithable: false)).not_to be_valid
  end

  it "applies the personal template to a personal book" do
    book = create(:business, :personal)
    CategoryTemplate.apply_to(book)
    expect(book.categories.find_by!(name: "Tithe")).to be_tithe
    expect(book.categories.find_by!(name: "Refunds and reimbursements")).not_to be_tithable
    expect(book.categories.where.not(schedule_c_line: nil)).to be_empty
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/business_spec.rb spec/models/household_spec.rb spec/models/category_spec.rb`
Expected: FAIL (unknown trait `personal`, unknown attribute `tithable`).

- [ ] **Step 3: Migrations**

`db/migrate/20261008000001_add_personal_book_to_businesses.rb`:

```ruby
class AddPersonalBookToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :kind, :string, null: false, default: "business"
    add_column :businesses, :tithe_start_on, :date
    change_column_null :businesses, :person_id, true
    add_index :businesses, :household_id, unique: true, where: "kind = 'personal'", name: "index_businesses_one_personal_per_household"
  end
end
```

`db/migrate/20261008000002_add_tithe_flags_to_categories.rb`:

```ruby
class AddTitheFlagsToCategories < ActiveRecord::Migration[8.1]
  def change
    change_column_null :categories, :schedule_c_line, true
    add_column :categories, :tithable, :boolean, null: false, default: true
    add_column :categories, :tithe, :boolean, null: false, default: false
  end
end
```

Run: `bin/rails db:migrate && RAILS_ENV=test bin/rails db:test:prepare`. Confirm `db/schema.rb` shows the new columns, `person_id` without `null: false`, and the partial index.

- [ ] **Step 4: Models**

`app/models/business.rb`: make the person optional, add the enum, scopes, and validations:

```ruby
class Business < ApplicationRecord
  belongs_to :household
  belongs_to :person, optional: true
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :accounts, dependent: :destroy
  has_many :rules, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :mileage_entries, dependent: :destroy
  has_many :clients, dependent: :restrict_with_error
  has_many :invoices, dependent: :restrict_with_error
  has_many :transactions, through: :accounts

  enum :kind, { business: "business", personal: "personal" }, validate: true, scopes: false

  scope :active, -> { where(archived_at: nil) }
  scope :business_kind, -> { where(kind: "business") }
  scope :personal, -> { where(kind: "personal") }

  validates :name, presence: true
  validates :person, presence: true, if: :business?
  validates :kind, uniqueness: { scope: :household_id, message: "already exists for this household" }, if: :personal?
  validate :person_in_household
  validate :personal_has_no_person
  validate :tithe_start_on_allowed
  validate :personal_not_archived

  private

  def person_in_household
    errors.add(:person, "must belong to this household") if person && person.household_id != household_id
  end

  def personal_has_no_person
    errors.add(:person, "must be blank for the personal book") if personal? && person_id.present?
  end

  def tithe_start_on_allowed
    return if tithe_start_on.nil?

    if business? then errors.add(:tithe_start_on, "is only for the personal book")
    elsif tithe_start_on > Date.current then errors.add(:tithe_start_on, "can't be in the future")
    end
  end

  def personal_not_archived
    errors.add(:base, "The personal book can't be archived") if personal? && archived_at.present?
  end
end
```

`app/models/household.rb`: add

```ruby
  def personal_book = businesses.personal.first
```

`app/models/category.rb`: add the callback and validation, and teach the Schedule C check about personal books:

```ruby
  before_validation :normalize_tithe_flags
  validate :tithe_flags_only_on_personal
```

(next to the existing `validate` lines), and replace `schedule_c_line_matches_kind` and add the two new private methods:

```ruby
  def schedule_c_line_matches_kind
    if business&.personal?
      errors.add(:schedule_c_line, "must be blank for personal categories") if schedule_c_line.present?
      return
    end

    allowed = ScheduleC.options_for(kind).map(&:last)
    errors.add(:schedule_c_line, "is not valid for #{kind} categories") unless allowed.include?(schedule_c_line)
  end

  # Tithable only means something on income, tithe only on expense; the form shows both, so normalize instead of erroring.
  def normalize_tithe_flags
    self.tithable = true if expense?
    self.tithe = false if income?
  end

  def tithe_flags_only_on_personal
    return if business&.personal? || (tithable? && !tithe?)

    errors.add(:base, "Tithe settings are only for personal categories")
  end
```

`app/models/category_template.rb`: add the personal list and pick by kind:

```ruby
  PERSONAL = [
    { name: "Owner draws", kind: "income" },
    { name: "Paychecks and other income", kind: "income" },
    { name: "Refunds and reimbursements", kind: "income", tithable: false },
    { name: "Tithe", kind: "expense", tithe: true },
    { name: "Offerings and giving", kind: "expense" },
    { name: "Groceries", kind: "expense" },
    { name: "Dining", kind: "expense" },
    { name: "Housing", kind: "expense" },
    { name: "Utilities", kind: "expense" },
    { name: "Transportation", kind: "expense" },
    { name: "Insurance", kind: "expense" },
    { name: "Medical", kind: "expense" },
    { name: "Kids", kind: "expense" },
    { name: "Household", kind: "expense" },
    { name: "Personal", kind: "expense" },
    { name: "Gifts", kind: "expense" },
    { name: "Subscriptions", kind: "expense" },
    { name: "Other", kind: "expense" }
  ].freeze

  def self.apply_to(business)
    (business.personal? ? PERSONAL : CATEGORIES).each { |attrs| business.categories.create!(attrs) }
  end
```

- [ ] **Step 5: Factories**

`spec/factories/businesses.rb`: add inside the factory:

```ruby
    trait :personal do
      kind { "personal" }
      person { nil }
      name { "Personal" }
    end
```

`spec/factories/categories.rb`: make the line follow the book:

```ruby
FactoryBot.define do
  factory :category do
    business
    sequence(:name) { |n| "Category #{n}" }
    kind { "expense" }
    schedule_c_line { business.personal? ? nil : "18" }

    trait :income do
      kind { "income" }
      schedule_c_line { business.personal? ? nil : "1" }
    end
  end
end
```

- [ ] **Step 6: Run the specs, then the full suite**

Run: `bundle exec rspec spec/models/business_spec.rb spec/models/household_spec.rb spec/models/category_spec.rb` → PASS.
Run: `bundle exec rspec` → 0 failures (existing business specs still pass because `kind` defaults to `business`). `bin/rubocop` → no offenses.

- [ ] **Step 7: Commit**

```bash
git add db app/models spec
git commit -m "Personal book: Business kind, tithe flags on categories, personal template"
```

---

### Task 2: Provision the personal book, memberships, nav entry

**Files:**
- Create: `app/services/personal_book_provisioner.rb`, `app/controllers/personal_books_controller.rb`, `spec/services/personal_book_provisioner_spec.rb`, `spec/requests/personal_books_spec.rb`
- Modify: `config/routes.rb`, `app/controllers/people_controller.rb`, `app/helpers/application_helper.rb`, `app/views/layouts/application.html.erb`, `app/views/dashboards/show.html.erb`, `spec/requests/people_spec.rb`

**Interfaces:**
- Consumes: `Household#personal_book`, `CategoryTemplate.apply_to`, `create(:business, :personal)` (Task 1).
- Produces: `PersonalBookProvisioner.call(household) → Business` (idempotent), `PersonalBookProvisioner.sync(household)` (grants memberships if a book exists); route `personal_book_path` (POST); helper `current_personal_book` (the signed-in user's personal book or nil).

- [ ] **Step 1: Write the failing specs**

`spec/services/personal_book_provisioner_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PersonalBookProvisioner do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }

  it "creates the book once, with personal categories and no Cash account" do
    book = described_class.call(household)
    expect(book).to be_personal
    expect(book.name).to eq("Personal")
    expect(book.accounts).to be_empty
    expect(book.categories.find_by!(name: "Tithe")).to be_tithe
    expect(described_class.call(household)).to eq(book)
    expect(Business.personal.count).to eq(1)
  end

  it "makes the household owner an owner and linked people editors, never the accountant" do
    spouse = create(:user)
    create(:person, household: household, user: spouse)
    accountant = create(:user)
    book = described_class.call(household)
    expect(owner.membership_for(book)).to be_owner
    expect(spouse.membership_for(book)).to be_editor
    expect(accountant.membership_for(book)).to be_nil
  end

  it "sync grants newly linked people and does nothing without a book" do
    spouse = create(:user)
    expect { described_class.sync(household) }.not_to change(Membership, :count)
    book = described_class.call(household)
    create(:person, household: household, user: spouse)
    described_class.sync(household)
    expect(spouse.membership_for(book)).to be_editor
  end
end
```

`spec/requests/personal_books_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Personal book" do
  let!(:household) { create(:household) }

  it "lets the household owner set it up from the dashboard" do
    owner = create(:user, :household_owner)
    sign_in_as owner
    get root_path
    expect(response.body).to include("Set up personal book")
    post personal_book_path
    book = Business.personal.sole
    expect(response).to redirect_to(business_path(book))
    get root_path
    expect(response.body).to include(%(href="#{business_path(book)}"))
    expect(response.body).not_to include("Set up personal book")
  end

  it "is not found for anyone else" do
    business = create(:business)
    sign_in_as user_with_role("owner", business)
    post personal_book_path
    expect(response).to have_http_status(:not_found)
    expect(Business.personal).to be_empty
  end
end
```

Append to `spec/requests/people_spec.rb` (inside the top-level `describe`):

```ruby
  it "gives a newly linked spouse editor access to the personal book" do
    book = PersonalBookProvisioner.call(household)
    spouse_user = create(:user)
    sign_in_as household_owner
    patch person_path(spouse), params: { person: { name: "Jordan", user_id: spouse_user.id } }
    expect(spouse_user.membership_for(book)).to be_editor
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/services/personal_book_provisioner_spec.rb spec/requests/personal_books_spec.rb spec/requests/people_spec.rb`
Expected: FAIL (`uninitialized constant PersonalBookProvisioner`, no route).

- [ ] **Step 3: Service**

`app/services/personal_book_provisioner.rb`:

```ruby
# Creates the household's single personal book and keeps its memberships in step with the household:
# household owners are owners, users linked to a Person are editors. The accountant never gets one.
class PersonalBookProvisioner
  NAME = "Personal"

  def self.call(household)
    household.with_lock do
      book = household.personal_book || household.businesses.create!(kind: "personal", name: NAME).tap { CategoryTemplate.apply_to(_1) }
      sync_memberships(book)
      book
    end
  end

  def self.sync(household)
    book = household.personal_book
    sync_memberships(book) if book
  end

  def self.sync_memberships(book)
    User.where(household_owner: true).find_each { grant(book, _1, "owner") }
    User.where(household_owner: false, id: book.household.people.select(:user_id)).find_each { grant(book, _1, "editor") }
  end

  def self.grant(book, user, role)
    book.memberships.find_or_create_by!(user: user) { _1.role = role }
  end

  private_class_method :sync_memberships, :grant
end
```

- [ ] **Step 4: Route, controller, people hook**

`config/routes.rb`: add after `resources :people ...`:

```ruby
  resource :personal_book, only: :create
```

`app/controllers/personal_books_controller.rb`:

```ruby
class PersonalBooksController < ApplicationController
  def create
    return head :not_found unless Current.user.household_owner?

    book = PersonalBookProvisioner.call(Household.instance)
    redirect_to business_path(book), notice: "Personal book ready."
  end
end
```

`app/controllers/people_controller.rb`: after a successful save in `create` and `update`, sync. Change the two success branches to:

```ruby
    if household.with_lock { @person.save }
      PersonalBookProvisioner.sync(household)
      redirect_to people_path, notice: "Person added."
```

```ruby
    if @person.update(person_params)
      PersonalBookProvisioner.sync(Household.instance)
      redirect_to people_path, notice: "Person updated."
```

- [ ] **Step 5: Nav and dashboard**

`app/helpers/application_helper.rb`: add

```ruby
  def current_personal_book
    return @current_personal_book if defined?(@current_personal_book)

    @current_personal_book = Current.user.accessible_businesses.personal.first
  end
```

`app/views/layouts/application.html.erb`: in `.site-nav`, after the "Inbox" link:

```erb
          <%= link_to "Personal", business_path(current_personal_book) if current_personal_book %>
```

`app/views/dashboards/show.html.erb`: append

```erb
<% if current_personal_book %>
  <h2>Personal</h2>
  <p><%= link_to "Personal", business_path(current_personal_book) %></p>
<% elsif Current.user.household_owner? %>
  <h2>Personal</h2>
  <p>Track the joint checking account and the tithe. The accountant never sees it.</p>
  <%= button_to "Set up personal book", personal_book_path %>
<% end %>
```

- [ ] **Step 6: Run the specs and the suite**

Run: `bundle exec rspec spec/services/personal_book_provisioner_spec.rb spec/requests/personal_books_spec.rb spec/requests/people_spec.rb` → PASS. `bundle exec rspec` → 0 failures. `bin/rubocop` → clean.

Note: the personal book still appears in the dashboard's business list until Task 6; that is expected here.

- [ ] **Step 7: Commit**

```bash
git add app config spec
git commit -m "Personal book: provisioning, owner and spouse memberships, nav entry"
```

---

### Task 3: Pure weekly tithe ledger

**Files:**
- Create: `app/models/tithe/ledger.rb`, `spec/models/tithe/ledger_spec.rb`

**Interfaces:**
- Produces: `Tithe::Ledger.week_start(date) → Date` (the Sunday on or before); `Tithe::Ledger::Entry = Data.define(:posted_on, :cents, :kind, :source)` with `kind` `:income` or `:payment` (for payments `cents` is the amount paid; a refunded tithe is negative); `Tithe::Ledger.new(entries:, start_on:, today:)` exposing `weeks` (array of `Tithe::Ledger::Week` with `starts_on, ends_on, income_cents, owed_cents, paid_cents, paid_toward_cents, status ("paid"|"partial"|"open"), balance_cents, entries`), and `owed_cents, paid_cents, balance_cents, credit_cents, ytd_owed_cents, ytd_paid_cents`. `balance_cents` positive = behind.

- [ ] **Step 1: Write the failing spec**

`spec/models/tithe/ledger_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tithe::Ledger do
  def income(date, cents) = Tithe::Ledger::Entry.new(posted_on: Date.parse(date), cents: cents, kind: :income, source: nil)
  def paid(date, cents) = Tithe::Ledger::Entry.new(posted_on: Date.parse(date), cents: cents, kind: :payment, source: nil)
  def ledger(entries, start_on: "2026-01-04", today: "2026-01-24")
    described_class.new(entries: entries, start_on: Date.parse(start_on), today: Date.parse(today))
  end

  it "starts weeks on Sunday" do
    expect(described_class.week_start(Date.new(2026, 1, 10))).to eq(Date.new(2026, 1, 4)) # Saturday
    expect(described_class.week_start(Date.new(2026, 1, 11))).to eq(Date.new(2026, 1, 11)) # Sunday
  end

  it "puts Saturday and Sunday income in different weeks and lists every week through today" do
    result = ledger([ income("2026-01-10", 10_000), income("2026-01-11", 20_000) ])
    expect(result.weeks.map(&:starts_on).map(&:iso8601)).to eq(%w[2026-01-04 2026-01-11 2026-01-18])
    expect(result.weeks.map(&:owed_cents)).to eq([ 1_000, 2_000, 0 ])
    expect(result.weeks.last.status).to eq("paid")
  end

  it "rounds once per week, half up" do
    result = ledger([ income("2026-01-05", 333), income("2026-01-06", 333), income("2026-01-07", 333) ], today: "2026-01-07")
    expect(result.weeks.sole.owed_cents).to eq(100) # 99.9 → 100, not 3 × 33
    expect(ledger([ income("2026-01-05", 1_005) ], today: "2026-01-07").owed_cents).to eq(101)
  end

  it "ignores days before a mid-week start date and anything after today" do
    result = ledger([ income("2026-01-05", 50_000), income("2026-01-08", 10_000), income("2026-01-15", 70_000) ],
                    start_on: "2026-01-07", today: "2026-01-14")
    expect(result.weeks.map(&:starts_on).map(&:iso8601)).to eq(%w[2026-01-04 2026-01-11])
    expect(result.owed_cents).to eq(1_000)
  end

  it "applies payments to the oldest week first and keeps a running balance" do
    entries = [ income("2026-01-05", 10_000), income("2026-01-12", 10_000), income("2026-01-19", 10_000), paid("2026-01-20", 2_500) ]
    result = ledger(entries)
    expect(result.weeks.map(&:status)).to eq(%w[paid paid partial])
    expect(result.weeks.map(&:paid_toward_cents)).to eq([ 1_000, 1_000, 500 ])
    expect(result.weeks.map(&:paid_cents)).to eq([ 0, 0, 2_500 ])
    expect(result.weeks.map(&:balance_cents)).to eq([ 1_000, 2_000, 500 ])
    expect(result.balance_cents).to eq(500)
    expect(result.credit_cents).to eq(0)
  end

  it "leaves later weeks open when payments run out" do
    result = ledger([ income("2026-01-05", 10_000), income("2026-01-12", 10_000), paid("2026-01-06", 400) ], today: "2026-01-17")
    expect(result.weeks.map(&:status)).to eq(%w[partial open])
  end

  it "carries an overpayment as credit" do
    result = ledger([ income("2026-01-05", 10_000), paid("2026-01-06", 1_500) ], today: "2026-01-07")
    expect(result.balance_cents).to eq(-500)
    expect(result.credit_cents).to eq(500)
    expect(result.weeks.sole.status).to eq("paid")
  end

  it "subtracts a refunded tithe from paid" do
    result = ledger([ income("2026-01-05", 10_000), paid("2026-01-06", 1_000), paid("2026-01-07", -1_000) ], today: "2026-01-08")
    expect(result.paid_cents).to eq(0)
    expect(result.weeks.sole.status).to eq("open")
  end

  it "keeps each week's entries, oldest first" do
    a = income("2026-01-06", 100)
    b = paid("2026-01-05", 10)
    expect(ledger([ a, b ], today: "2026-01-07").weeks.sole.entries).to eq([ b, a ])
  end

  it "counts year to date by the year each week ends in" do
    result = ledger([ income("2025-12-22", 10_000), income("2025-12-29", 20_000), paid("2026-01-02", 500) ],
                    start_on: "2025-12-21", today: "2026-01-05")
    expect(result.ytd_owed_cents).to eq(2_000) # week of Dec 28 ends Jan 3, 2026; plus the empty week of Jan 4
    expect(result.ytd_paid_cents).to eq(500)
  end

  it "has no weeks when the start date is after today" do
    result = ledger([], start_on: "2026-02-01", today: "2026-01-05")
    expect(result.weeks).to be_empty
    expect(result.balance_cents).to eq(0)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/models/tithe/ledger_spec.rb`
Expected: FAIL (`uninitialized constant Tithe`).

- [ ] **Step 3: Implement**

`app/models/tithe/ledger.rb`:

```ruby
module Tithe
  # Weekly tithe owed vs. paid (spec §4). Pure: entries in, Sunday–Saturday weeks out.
  # Owed is 10% of each week's income, rounded once per week. Payments settle the oldest weeks first;
  # the running balance uses actual payment dates. Positive balance = behind.
  class Ledger
    RATE = Rational(1, 10)
    Entry = Data.define(:posted_on, :cents, :kind, :source)
    Week = Data.define(:starts_on, :ends_on, :income_cents, :owed_cents, :paid_cents, :paid_toward_cents, :status, :balance_cents, :entries)

    attr_reader :weeks, :owed_cents, :paid_cents, :balance_cents, :credit_cents, :ytd_owed_cents, :ytd_paid_cents

    def self.week_start(date) = date - date.wday

    def initialize(entries:, start_on:, today:)
      by_week = entries.select { _1.posted_on.between?(start_on, today) }.group_by { self.class.week_start(_1.posted_on) }
      starts = start_on > today ? [] : self.class.week_start(start_on).step(self.class.week_start(today), 7).to_a
      @owed_cents = 0
      @paid_cents = 0
      totals = starts.map do |starts_on|
        week_entries = (by_week[starts_on] || []).sort_by(&:posted_on)
        income = week_entries.select { _1.kind == :income }.sum(&:cents)
        paid = week_entries.select { _1.kind == :payment }.sum(&:cents)
        owed = Money.round_rational(income * RATE)
        @owed_cents += owed
        @paid_cents += paid
        { starts_on:, income:, owed:, paid:, balance: @owed_cents - @paid_cents, entries: week_entries }
      end
      @balance_cents = @owed_cents - @paid_cents
      @credit_cents = [ -@balance_cents, 0 ].max
      @weeks = allocate(totals, [ @paid_cents, 0 ].max)
      this_year = @weeks.select { _1.ends_on.year == today.year }
      @ytd_owed_cents = this_year.sum(&:owed_cents)
      @ytd_paid_cents = this_year.sum(&:paid_cents)
    end

    private

    def allocate(totals, remaining)
      totals.map do |w|
        toward = [ w[:owed], remaining ].min
        remaining -= toward
        Week.new(starts_on: w[:starts_on], ends_on: w[:starts_on] + 6, income_cents: w[:income], owed_cents: w[:owed],
                 paid_cents: w[:paid], paid_toward_cents: toward, status: status_for(w[:owed], toward),
                 balance_cents: w[:balance], entries: w[:entries])
      end
    end

    def status_for(owed, toward)
      if toward == owed then "paid"
      elsif toward.positive? then "partial"
      else "open"
      end
    end
  end
end
```

Note: `sort_by(&:posted_on)` is stable in practice for the spec's `[b, a]` case because the dates differ; do not rely on order within a day.

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec rspec spec/models/tithe/ledger_spec.rb` → PASS. `bin/rubocop` → clean.

- [ ] **Step 5: Commit**

```bash
git add app/models/tithe spec/models/tithe
git commit -m "Tithe: pure weekly ledger with FIFO allocation and running balance"
```

---

### Task 4: Tithe entries from transactions

**Files:**
- Create: `app/models/tithe.rb`, `app/models/tithe/entries.rb`, `spec/models/tithe/entries_spec.rb`

**Interfaces:**
- Consumes: `Tithe::Ledger`, `Tithe::Ledger::Entry` (Task 3); `Category#tithable?`/`#tithe?`, `Business#tithe_start_on` (Task 1).
- Produces: `Tithe::Entries.for(book) → Array<Tithe::Ledger::Entry>` (`source` is the `Transaction`); `Tithe.ledger_for(book, today: Date.current) → Tithe::Ledger | nil` (nil when `tithe_start_on` is blank).

- [ ] **Step 1: Write the failing spec**

`spec/models/tithe/entries_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tithe::Entries do
  let(:book) { create(:business, :personal, tithe_start_on: Date.new(2026, 1, 4)) }
  let(:checking) { create(:account, business: book) }
  let(:savings) { create(:account, business: book) }
  let(:draws) { create(:category, :income, business: book, name: "Owner draws") }
  let(:refunds) { create(:category, :income, business: book, name: "Refunds", tithable: false) }
  let(:groceries) { create(:category, business: book, name: "Groceries") }
  let(:tithe) { create(:category, business: book, name: "Tithe", tithe: true) }

  def txn(cents, account: checking, on: Date.new(2026, 1, 6), **attrs)
    create(:transaction, account: account, amount_cents: cents, posted_on: on, **attrs)
  end

  def kinds = described_class.for(book).map { [ _1.kind, _1.cents ] }

  it "counts uncategorized deposits and tithable income across the book's accounts" do
    txn(10_000)
    txn(20_000, account: savings, category: draws)
    expect(kinds).to contain_exactly([ :income, 10_000 ], [ :income, 20_000 ])
  end

  it "skips not-tithable income, transfers, excluded rows, and days before the start date" do
    txn(5_000, category: refunds)
    txn(6_000, transfer: true)
    txn(7_000, excluded: true)
    txn(8_000, on: Date.new(2026, 1, 3))
    expect(kinds).to be_empty
  end

  it "never treats a positive amount in an expense category as income" do
    txn(2_500, category: groceries)
    expect(kinds).to be_empty
  end

  it "turns tithe-category rows into payments, with refunds negative" do
    check = txn(-30_000, category: tithe)
    txn(5_000, category: tithe)
    expect(kinds).to contain_exactly([ :payment, 30_000 ], [ :payment, -5_000 ])
    expect(described_class.for(book).find { _1.cents == 30_000 }.source).to eq(check)
  end

  it "ignores other books" do
    create(:transaction, amount_cents: 10_000, posted_on: Date.new(2026, 1, 6))
    expect(kinds).to be_empty
  end

  it "builds a ledger only when a start date is set" do
    txn(10_000)
    expect(Tithe.ledger_for(book, today: Date.new(2026, 1, 10)).owed_cents).to eq(1_000)
    book.update!(tithe_start_on: nil)
    expect(Tithe.ledger_for(book)).to be_nil
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/models/tithe/entries_spec.rb`
Expected: FAIL (`uninitialized constant Tithe::Entries`).

- [ ] **Step 3: Implement**

`app/models/tithe.rb`:

```ruby
module Tithe
  def self.ledger_for(book, today: Date.current)
    return unless book.tithe_start_on

    Ledger.new(entries: Entries.for(book), start_on: book.tithe_start_on, today: today)
  end
end
```

`app/models/tithe/entries.rb`:

```ruby
module Tithe
  # The only place that knows which transactions are tithable income or tithe payments (spec §4).
  module Entries
    TITHABLE_INCOME_SQL = "categories.id IS NULL OR (categories.kind = 'income' AND categories.tithable = ?)".freeze

    def self.for(book)
      return [] unless book.tithe_start_on

      scope = Transaction.countable.for_businesses(book.id).where(posted_on: book.tithe_start_on..)
      income = scope.where("transactions.amount_cents > 0").left_joins(:category).where(TITHABLE_INCOME_SQL, true)
      payments = scope.joins(:category).where(categories: { tithe: true })
      income.map { Ledger::Entry.new(posted_on: _1.posted_on, cents: _1.amount_cents, kind: :income, source: _1) } +
        payments.map { Ledger::Entry.new(posted_on: _1.posted_on, cents: -_1.amount_cents, kind: :payment, source: _1) }
    end
  end
end
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec rspec spec/models/tithe` → PASS. `bin/rubocop` and `bin/brakeman --no-pager -q` → clean (the SQL fragment is a constant with a bind).

- [ ] **Step 5: Commit**

```bash
git add app/models/tithe.rb app/models/tithe spec/models/tithe
git commit -m "Tithe: entries from personal-book transactions"
```

---

### Task 5: Personal-book screens: business-only 404s, nav, categories

**Files:**
- Create: `app/controllers/concerns/business_kind_only.rb`, `app/controllers/concerns/personal_only.rb`, `app/helpers/categories_helper.rb`, `spec/requests/personal_book_screens_spec.rb`
- Modify: `app/controllers/{clients,invoices,invoice_payments,invoice_pdfs,mileage_entries,mileage_logs,schedule_cs,profit_and_losses,invoice_agings}_controller.rb`, `app/controllers/businesses_controller.rb`, `app/controllers/categories_controller.rb`, `app/views/businesses/_nav.html.erb`, `app/views/businesses/show.html.erb`, `app/views/categories/_form.html.erb`, `app/views/categories/index.html.erb`, `app/models/reports/transaction_csv.rb`, `spec/models/reports/csv_spec.rb`

**Interfaces:**
- Consumes: `Business#personal?` (Task 1), `PersonalBookProvisioner` (Task 2).
- Produces: concerns `BusinessKindOnly` (before_action raising `ActiveRecord::RecordNotFound` on a personal book) and `PersonalOnly` (the inverse), both included **after** `BusinessScoped`; helper `category_tithe_label(category)`.

- [ ] **Step 1: Write the failing specs**

`spec/requests/personal_book_screens_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Personal book screens" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:book) { PersonalBookProvisioner.call(household) }

  before { sign_in_as owner }

  it "404s every business-only screen" do
    paths = [
      business_clients_path(book), business_invoices_path(book), new_business_invoice_path(book),
      business_mileage_entries_path(book), business_mileage_log_path(book), business_schedule_c_path(book),
      business_profit_and_loss_path(book), business_invoice_aging_path(book)
    ]
    paths.each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
    end
  end

  it "shows the shared screens with personal wording" do
    get business_path(book)
    expect(response.body).to include("Personal")
    expect(response.body).not_to include("Taxpayer", business_mileage_entries_path(book), business_invoices_path(book), business_schedule_c_path(book))
    [ business_accounts_path(book), business_transactions_path(book), business_rules_path(book), business_inbox_path(book) ].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
    end
  end

  it "lists categories with tithe labels instead of Schedule C" do
    get business_categories_path(book)
    expect(response.body).to include("Tithe payment", "Not tithable", "Tithable")
    expect(response.body).not_to include("Line ")
  end

  it "creates personal categories with tithe flags and no Schedule C line" do
    post business_categories_path(book), params: { category: { name: "Mission trip", kind: "expense", tithable: "0", tithe: "1" } }
    expect(response).to redirect_to(business_categories_path(book))
    category = book.categories.find_by!(name: "Mission trip")
    expect(category).to be_tithe
    expect(category.schedule_c_line).to be_nil
    get new_business_category_path(book)
    expect(response.body).to include("category[tithe]")
    expect(response.body).not_to include("category[schedule_c_line]")
  end

  it "rejects a crafted tithe flag on a business category" do
    business = create(:business)
    create(:membership, user: owner, business: business, role: "owner")
    post business_categories_path(business), params: { category: { name: "X", kind: "expense", schedule_c_line: "18", tithe: "1" } }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
```

In `spec/models/reports/csv_spec.rb`, add (inside the describe for `Reports::TransactionCsv`, or at top level):

```ruby
  it "leaves the deductible amount blank for personal expenses" do
    book = create(:business, :personal)
    txn = create(:transaction, account: create(:account, business: book), amount_cents: -5_000,
                               category: create(:category, business: book, name: "Groceries"))
    row = CSV.parse(Reports::TransactionCsv.generate([ txn ]), headers: true).first
    expect(row["Deductible amount"]).to be_nil
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/requests/personal_book_screens_spec.rb spec/models/reports/csv_spec.rb`
Expected: FAIL (business-only screens return 200; `Taxpayer` raises on nil person; categories show Schedule C).

- [ ] **Step 3: Concerns**

`app/controllers/concerns/business_kind_only.rb`:

```ruby
# Invoices, clients, mileage, Schedule C, and P&L don't exist for the personal book. Include after BusinessScoped.
module BusinessKindOnly
  extend ActiveSupport::Concern

  included do
    before_action :require_business_kind!
  end

  private

  def require_business_kind!
    raise ActiveRecord::RecordNotFound if @business.personal?
  end
end
```

`app/controllers/concerns/personal_only.rb`:

```ruby
# Tithe and spending screens exist only for the personal book. Include after BusinessScoped.
module PersonalOnly
  extend ActiveSupport::Concern

  included do
    before_action :require_personal!
  end

  private

  def require_personal!
    raise ActiveRecord::RecordNotFound unless @business.personal?
  end
end
```

Add `include BusinessKindOnly` on the line right after `include BusinessScoped` in each of: `ClientsController`, `InvoicesController`, `InvoicePaymentsController`, `InvoicePdfsController`, `MileageEntriesController`, `MileageLogsController`, `ScheduleCsController`, `ProfitAndLossesController`, `InvoiceAgingsController`.

- [ ] **Step 4: Business page and nav**

`app/controllers/businesses_controller.rb#show`:

```ruby
  def show
    @accounts = @business.accounts.active.order(:name)
    @receivables = Invoice.receivables_by_business([ @business.id ])[@business.id] if @business.business?
  end
```

`app/views/businesses/show.html.erb`: replace the two `<p>` lines after the `<h1>` with:

```erb
<% if @business.personal? %>
  <p>The household's personal accounts and tithe. Only household members can see this.</p>
<% else %>
  <p>Taxpayer: <%= @business.person.name %></p>
  <p><%= render "invoices/receivables", totals: @receivables %></p>
<% end %>
```

and change `link_to "Edit business"` to `link_to(@business.personal? ? "Rename" : "Edit business", edit_business_path(@business))`.

`app/views/businesses/_nav.html.erb`: wrap the business-only links:

```erb
    <% unless business.personal? %>
      <li><%= link_to "Mileage", business_mileage_entries_path(business) %></li>
      <li><%= link_to "Invoices", business_invoices_path(business) %></li>
      <li><%= link_to "Clients", business_clients_path(business) %></li>
      <li><%= link_to "P&L", business_profit_and_loss_path(business) %></li>
      <li><%= link_to "Schedule C", business_schedule_c_path(business) %></li>
      <li><%= link_to "Aging", business_invoice_aging_path(business) %></li>
    <% end %>
```

- [ ] **Step 5: Categories**

`app/controllers/categories_controller.rb`:

```ruby
  PERMITTED = %i[name kind schedule_c_line deductible_percent tithable tithe].freeze
```

(at the top of the class), then:

```ruby
  def new
    @category = @business.categories.new(kind: "expense", schedule_c_line: (@business.personal? ? nil : "18"))
  end

  def create
    @category = @business.categories.new(params.expect(category: PERMITTED))
```

and in `update`: `attrs = params.expect(category: [ *PERMITTED, :archived ])`.

`app/helpers/categories_helper.rb`:

```ruby
module CategoriesHelper
  def category_tithe_label(category)
    if category.income? then category.tithable? ? "Tithable" : "Not tithable"
    elsif category.tithe? then "Tithe payment"
    end
  end
end
```

`app/views/categories/_form.html.erb`: replace the Schedule C `<p>` block and the deductible `<p>` with:

```erb
  <% if @business.personal? %>
    <p><%= f.check_box :tithable %> <%= f.label :tithable, "Tithable (income: deposits here count toward the tithe)" %></p>
    <p><%= f.check_box :tithe %> <%= f.label :tithe, "Tithe payment (expense: payments here pay the tithe)" %></p>
  <% else %>
    <p>
      <%= f.label :schedule_c_line, "Schedule C line" %>
      <%= f.select :schedule_c_line, grouped_options_for_select(
            { "Income" => ScheduleC.options_for("income"), "Expense" => ScheduleC.options_for("expense") },
            category.schedule_c_line) %>
    </p>
    <p><%= f.label :deductible_percent, "Deductible %" %> <%= f.text_field :deductible_percent, size: 6 %></p>
  <% end %>
```

`app/views/categories/index.html.erb`: make the header and cells depend on the book:

```erb
  <thead>
    <tr>
      <th>Name</th><th>Kind</th>
      <% if @business.personal? %><th>Tithe</th><% else %><th>Schedule C</th><th class="num">Deductible</th><% end %>
      <th></th>
    </tr>
  </thead>
```

and in the row:

```erb
        <% if @business.personal? %>
          <td><%= category_tithe_label(category) %></td>
        <% else %>
          <td><%= ScheduleC.label(category.schedule_c_line) %></td>
          <td class="num"><%= category.deductible_percent %>%</td>
        <% end %>
```

- [ ] **Step 6: Transaction CSV**

`app/models/reports/transaction_csv.rb`: the expense branch only applies to business categories:

```ruby
            if category&.expense? && category.schedule_c_line then Money.round_rational(Rational(-txn.amount_cents * category.deductible_bps, 10_000))
            elsif category&.income? && category.schedule_c_line then txn.amount_cents
            end
```

- [ ] **Step 7: Run the specs and the suite**

Run: `bundle exec rspec spec/requests/personal_book_screens_spec.rb spec/models/reports/csv_spec.rb` → PASS. `bundle exec rspec` → 0 failures. `bin/rubocop` → clean.

- [ ] **Step 8: Commit**

```bash
git add app spec
git commit -m "Personal book: hide business-only screens, personal category form"
```

---

### Task 6: Keep the personal book out of household and cross-business paths

**Files:**
- Create: `spec/requests/personal_book_exclusions_spec.rb`
- Modify: `app/models/user.rb`, `app/models/invite.rb`, `app/controllers/{household_profit_and_losses,household_transaction_exports,household_invoices,household_invoice_agings,household_inboxes,dashboards,invites}_controller.rb`, `spec/models/user_household_access_spec.rb`

**Interfaces:**
- Consumes: `Business.business_kind`, `PersonalBookProvisioner` (Tasks 1–2).
- Produces: nothing new; behavior only.

- [ ] **Step 1: Write the failing specs**

`spec/requests/personal_book_exclusions_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Personal book exclusions" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:book) { PersonalBookProvisioner.call(household) }
  let!(:accountant) { user_with_role("viewer", business) }

  before do
    groceries = book.categories.find_by!(name: "Groceries")
    create(:transaction, account: create(:account, business: book), payee: "SECRET GROCER", amount_cents: -4_200,
                         posted_on: Date.current, category: groceries)
    create(:transaction, account: create(:account, business: business), payee: "OFFICE DEPOT", amount_cents: -1_000,
                         posted_on: Date.current, category: create(:category, business: business, name: "Office expense"))
  end

  it "keeps household access for the accountant, who has no personal membership" do
    expect(accountant.can_view_household?).to be(true)
  end

  it "404s every personal-book screen for the accountant" do
    sign_in_as accountant
    [ business_path(book), business_accounts_path(book), business_transactions_path(book), business_inbox_path(book),
      business_categories_path(book), business_rules_path(book) ].each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
    end
  end

  it "leaves personal rows out of household reports, exports, and the dashboard business list" do
    sign_in_as owner
    get household_profit_and_loss_path
    expect(response.body).to include("Pat Consulting", "Office expense")
    expect(response.body).not_to include("Groceries")
    get household_transaction_export_path
    expect(response.body).to include("OFFICE DEPOT")
    expect(response.body).not_to include("SECRET GROCER")
    get root_path
    expect(response.body.scan(%(href="#{business_path(book)}")).size).to eq(2) # site nav + Personal section, not the business list
  end

  it "shows the personal inbox group to members only" do
    Transaction.for_businesses(book.id).update_all(category_id: nil, categorized_by: nil)
    sign_in_as owner
    get household_inbox_path
    expect(response.body).to include("SECRET GROCER")
    sign_in_as accountant
    get household_inbox_path
    expect(response.body).not_to include("SECRET GROCER")
  end

  it "never grants the personal book through an invite" do
    sign_in_as owner
    get new_invite_path
    expect(response.body).not_to include("invite[grant_roles][#{book.id}]")
    expect {
      post invites_path, params: { invite: { grant_roles: { book.id.to_s => "viewer" } } }
    }.not_to change(Invite, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end
end
```

Before writing the dashboard expectation, check the site nav and dashboard markup produced in Task 2: the owner sees exactly two links to the book (nav "Personal" and the dashboard "Personal" section). If `get new_invite_path` names grant fields differently, adjust the `not_to include` string to the field name the form actually renders (see `app/views/invites/new.html.erb`).

Append to `spec/models/user_household_access_spec.rb` (inside the describe):

```ruby
  it "ignores the personal book when deciding household access" do
    business = create(:business)
    PersonalBookProvisioner.call(business.household)
    viewer = user_with_role("viewer", business)
    expect(viewer.can_view_household?).to be(true)
    personal_only = create(:user)
    create(:membership, user: personal_only, business: Business.personal.sole, role: "editor")
    expect(personal_only.can_view_household?).to be(false)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/requests/personal_book_exclusions_spec.rb spec/models/user_household_access_spec.rb`
Expected: FAIL (accountant loses household access; Groceries appears in household P&L; invite accepted).

- [ ] **Step 3: Implement**

`app/models/user.rb`:

```ruby
  def can_view_household?
    return true if household_owner?

    businesses = Business.business_kind
    memberships.where(business: businesses).exists? && businesses.where.not(id: memberships.select(:business_id)).none?
  end
```

`app/models/invite.rb` `grant_roles=`: `grants.build(business: Business.business_kind.find(business_id), role: role)`.

`app/controllers/invites_controller.rb#grantable_businesses`:

```ruby
  def grantable_businesses
    return Business.business_kind.active.order(:name) if Current.user.household_owner?

    Business.business_kind.active.where(id: Current.user.memberships.owner.select(:business_id)).order(:name)
  end
```

`app/controllers/household_profit_and_losses_controller.rb`: `businesses = Business.business_kind.order(:name).to_a`.

`app/controllers/household_transaction_exports_controller.rb`: `Transaction.for_businesses(Business.business_kind.select(:id))`.

`app/controllers/household_invoices_controller.rb` and `household_invoice_agings_controller.rb`: `Invoice.where(business_id: Business.business_kind.select(:id))`.

`app/controllers/household_inboxes_controller.rb`: `@matcher = InvoiceMatcher.for_businesses(businesses.select(&:business?).map(&:id))`.

`app/controllers/dashboards_controller.rb`: `@businesses = Current.user.accessible_businesses.business_kind.active.order(:name)`.

- [ ] **Step 4: Run the specs and the suite**

Run: `bundle exec rspec spec/requests/personal_book_exclusions_spec.rb spec/models/user_household_access_spec.rb` → PASS. `bundle exec rspec` → 0 failures. `bin/rubocop` → clean.

- [ ] **Step 5: Commit**

```bash
git add app spec
git commit -m "Personal book: exclude from household reports, access, invites, dashboard"
```

---

### Task 7: Tithe page, start date, CSV, dashboard card

**Files:**
- Create: `app/controllers/tithes_controller.rb`, `app/views/tithes/show.html.erb`, `app/helpers/tithes_helper.rb`, `app/models/reports/tithe_csv.rb`, `spec/requests/tithes_spec.rb`
- Modify: `config/routes.rb`, `app/views/businesses/_nav.html.erb`, `app/controllers/dashboards_controller.rb`, `app/views/dashboards/show.html.erb`

**Interfaces:**
- Consumes: `Tithe.ledger_for(book)` (Task 4), `PersonalOnly` (Task 5), `current_personal_book` (Task 2).
- Produces: routes `business_tithe_path(book)` (GET show, PATCH update, `format: :csv`); helpers `tithe_balance_label(cents)` → `"Behind $X"` / `"Ahead $X"` / `"Even"`, `tithe_week_label(week)`; `Reports::TitheCsv.generate(ledger)`.

- [ ] **Step 1: Write the failing spec**

`spec/requests/tithes_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Tithe" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:book) { PersonalBookProvisioner.call(household) }
  let(:checking) { create(:account, business: book) }
  let(:start_on) { Date.current - 14 }

  def seed_week
    create(:transaction, account: checking, payee: "TRANSFER FROM PAT", amount_cents: 150_000, posted_on: start_on)
    create(:transaction, account: checking, payee: "CHECK 1042 GRACE CHURCH", amount_cents: -10_000, posted_on: start_on + 1,
                         category: book.categories.find_by!(name: "Tithe"))
  end

  it "asks the owner for a start date before showing numbers" do
    sign_in_as owner
    get business_tithe_path(book)
    expect(response.body).to include("Track tithe from")
    expect(response.body).not_to include("Behind")
  end

  it "shows the balance, the weekly rows, and a CSV once a start date is set" do
    seed_week
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book)
    expect(response.body).to include("Behind $50.00", "TRANSFER FROM PAT", "CHECK 1042 GRACE CHURCH", "partial")
    get business_tithe_path(book, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body.lines.first).to start_with("Week starting,Week ending,Income,Owed")
    get root_path
    expect(response.body).to include("Tithe: Behind $50.00")
  end

  it "saves, rejects, and clears the start date" do
    sign_in_as owner
    patch business_tithe_path(book), params: { business: { tithe_start_on: start_on.iso8601 } }
    expect(response).to redirect_to(business_tithe_path(book))
    expect(book.reload.tithe_start_on).to eq(start_on)

    patch business_tithe_path(book), params: { business: { tithe_start_on: "abc" } }
    expect(flash[:alert]).to eq("Tithe start date is not a valid date.")
    expect(book.reload.tithe_start_on).to eq(start_on)

    patch business_tithe_path(book), params: { business: { tithe_start_on: (Date.current + 1).iso8601 } }
    expect(flash[:alert]).to include("can't be in the future")
    expect(book.reload.tithe_start_on).to eq(start_on)

    patch business_tithe_path(book), params: { business: { tithe_start_on: "" } }
    expect(book.reload.tithe_start_on).to be_nil
  end

  it "lets editors read but not change the start date" do
    spouse = create(:user)
    create(:person, household: household, user: spouse)
    PersonalBookProvisioner.sync(household)
    sign_in_as spouse
    get business_tithe_path(book)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Track tithe from")
    patch business_tithe_path(book), params: { business: { tithe_start_on: start_on.iso8601 } }
    expect(response).to have_http_status(:forbidden)
  end

  it "is not found for non-members and on business books" do
    business = create(:business)
    accountant = user_with_role("viewer", business)
    sign_in_as accountant
    get business_tithe_path(book)
    expect(response).to have_http_status(:not_found)
    get business_tithe_path(book, format: :csv)
    expect(response).to have_http_status(:not_found)
    sign_in_as user_with_role("owner", business)
    get business_tithe_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/requests/tithes_spec.rb`
Expected: FAIL (`undefined method 'business_tithe_path'`).

- [ ] **Step 3: Route**

`config/routes.rb`, inside `resources :businesses do`:

```ruby
    resource :tithe, only: %i[show update], controller: "tithes"
```

- [ ] **Step 4: Controller, helper, CSV**

`app/controllers/tithes_controller.rb`:

```ruby
class TithesController < ApplicationController
  include BusinessScoped
  include PersonalOnly

  before_action :require_owner!, only: :update

  def show
    @ledger = Tithe.ledger_for(@business)
    respond_to do |format|
      format.html
      format.csv do
        if @ledger
          send_data Reports::TitheCsv.generate(@ledger), filename: "tithe-#{Date.current}.csv", type: "text/csv"
        else
          head :not_found
        end
      end
    end
  end

  def update
    raw = params.expect(business: %i[tithe_start_on])[:tithe_start_on].to_s
    start_on = parse_iso_date(raw)
    if raw.present? && start_on.nil?
      redirect_to business_tithe_path(@business), alert: "Tithe start date is not a valid date."
    elsif @business.update(tithe_start_on: start_on)
      redirect_to business_tithe_path(@business), notice: start_on ? "Tithe start date saved." : "Tithe tracking turned off."
    else
      redirect_to business_tithe_path(@business), alert: @business.errors.full_messages.to_sentence
    end
  end

  private

  def parse_iso_date(value)
    Date.iso8601(value)
  rescue ArgumentError
    nil
  end
end
```

`app/helpers/tithes_helper.rb`:

```ruby
module TithesHelper
  def tithe_balance_label(cents)
    if cents.positive? then "Behind #{money(cents)}"
    elsif cents.negative? then "Ahead #{money(-cents)}"
    else "Even"
    end
  end

  def tithe_week_label(week) = "#{week.starts_on.strftime("%b %-d")} – #{week.ends_on.strftime("%b %-d, %Y")}"
end
```

`app/models/reports/tithe_csv.rb`:

```ruby
require "csv"

module Reports
  module TitheCsv
    HEADERS = [ "Week starting", "Week ending", "Income", "Owed", "Paid this week", "Applied to this week", "Status", "Balance" ].freeze

    def self.generate(ledger)
      CSV.generate do |csv|
        csv << HEADERS
        ledger.weeks.each do |week|
          amounts = [ week.income_cents, week.owed_cents, week.paid_cents, week.paid_toward_cents ].map { Money.new(_1).to_input }
          csv << [ week.starts_on.iso8601, week.ends_on.iso8601, *amounts, week.status, Money.new(week.balance_cents).to_input ]
        end
      end
    end
  end
end
```

- [ ] **Step 5: View**

`app/views/tithes/show.html.erb`:

```erb
<%= business_nav @business %>
<h1>Tithe</h1>
<% if current_membership.owner? %>
  <%= form_with model: @business, url: business_tithe_path(@business), method: :patch, class: "inline-form" do |f| %>
    <%= f.label :tithe_start_on, "Track tithe from" %>
    <%= f.date_field :tithe_start_on %>
    <%= f.submit "Save" %>
  <% end %>
<% end %>
<% if @ledger.nil? %>
  <p><%= current_membership.owner? ? "Choose the date to start tracking from; earlier activity is ignored." : "The household owner hasn't set a tithe start date yet." %></p>
<% else %>
  <p class="tithe-balance"><strong><%= tithe_balance_label(@ledger.balance_cents) %></strong></p>
  <p>This year: owed <%= money(@ledger.ytd_owed_cents) %> · paid <%= money(@ledger.ytd_paid_cents) %></p>
  <p><%= link_to "Download CSV", business_tithe_path(@business, format: :csv) %></p>
  <table>
    <thead>
      <tr><th>Week</th><th class="num">Income</th><th class="num">Owed</th><th class="num">Paid this week</th><th class="num">Applied</th><th>Status</th><th class="num">Balance</th></tr>
    </thead>
    <tbody>
      <% @ledger.weeks.reverse_each do |week| %>
        <tr>
          <td>
            <details>
              <summary><%= tithe_week_label(week) %></summary>
              <ul>
                <% week.entries.each do |entry| %>
                  <li><%= entry.posted_on.iso8601 %> <%= entry.source.payee %> (<%= entry.kind == :income ? "income" : "tithe" %>) <%= money(entry.cents) %></li>
                <% end %>
              </ul>
            </details>
          </td>
          <td class="num"><%= money(week.income_cents) %></td>
          <td class="num"><%= money(week.owed_cents) %></td>
          <td class="num"><%= money(week.paid_cents) %></td>
          <td class="num"><%= money(week.paid_toward_cents) %></td>
          <td><%= week.status %></td>
          <td class="num"><%= tithe_balance_label(week.balance_cents) %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>
```

`app/views/businesses/_nav.html.erb`: before the `<% unless business.personal? %>` block, add:

```erb
    <% if business.personal? %>
      <li><%= link_to "Tithe", business_tithe_path(business) %></li>
    <% end %>
```

- [ ] **Step 6: Dashboard card**

`app/controllers/dashboards_controller.rb#show`: add

```ruby
    book = Current.user.accessible_businesses.personal.first
    @tithe = book && Tithe.ledger_for(book)
```

`app/views/dashboards/show.html.erb`: in the `if current_personal_book` branch, after the Personal link paragraph:

```erb
  <% if @tithe %>
    <p><%= link_to "Tithe: #{tithe_balance_label(@tithe.balance_cents)}", business_tithe_path(current_personal_book) %></p>
  <% end %>
```

Note: this adds a third `href` to the book's tithe path, not to `business_path(book)`, so Task 6's link-count expectation still holds. Run it to confirm.

- [ ] **Step 7: Run the specs and the suite**

Run: `bundle exec rspec spec/requests/tithes_spec.rb` → PASS. `bundle exec rspec` → 0 failures. `bin/rubocop`, `bin/brakeman --no-pager -q` → clean.

- [ ] **Step 8: Commit**

```bash
git add app config spec
git commit -m "Tithe: weekly page, start date, CSV export, dashboard balance"
```

---

### Task 8: Personal spending report

**Files:**
- Create: `app/models/reports/spending.rb`, `app/models/reports/spending_csv.rb`, `app/controllers/spending_reports_controller.rb`, `app/views/spending_reports/show.html.erb`, `spec/models/reports/spending_spec.rb`, `spec/requests/spending_reports_spec.rb`
- Modify: `config/routes.rb`, `app/views/businesses/_nav.html.erb`

**Interfaces:**
- Consumes: `PersonalOnly` (Task 5), `DateRangeParams` (existing).
- Produces: `Reports::Spending::Row = Data.define(:month, :category_name, :kind, :sum_cents)` (`month` is `"YYYY-MM"`), `Reports::Spending.months_in(range) → Array<String>`, `Reports::Spending.load(business_id:, range:) → Array<Row>`, `Reports::Spending.new(rows, months:)` exposing `months, income_lines, expense_lines, income_total, expense_total, net` (each line a `Reports::Spending::Line` with `name, amounts (Hash month → cents), total_cents`); `Reports::SpendingCsv.generate(report)`; route `business_spending_report_path(book)`.

- [ ] **Step 1: Write the failing specs**

`spec/models/reports/spending_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Reports::Spending do
  def row(month, name, kind, cents) = described_class::Row.new(month: month, category_name: name, kind: kind, sum_cents: cents)

  it "lists the months a range touches" do
    expect(described_class.months_in(Date.new(2026, 1, 15)..Date.new(2026, 3, 1))).to eq(%w[2026-01 2026-02 2026-03])
  end

  it "builds income and expense grids, expenses shown positive, with totals and net" do
    report = described_class.new([ row("2026-01", "Groceries", "expense", -30_000), row("2026-02", "Groceries", "expense", -20_000),
                                   row("2026-02", "Groceries", "expense", 1_000), row("2026-01", "Owner draws", "income", 600_000) ],
                                 months: %w[2026-01 2026-02])
    groceries = report.expense_lines.sole
    expect(groceries.amounts).to eq("2026-01" => 30_000, "2026-02" => 19_000)
    expect(groceries.total_cents).to eq(49_000)
    expect(report.income_total.amounts).to eq("2026-01" => 600_000, "2026-02" => 0)
    expect(report.net.amounts).to eq("2026-01" => 570_000, "2026-02" => -19_000)
    expect(report.net.total_cents).to eq(551_000)
  end

  it "loads grouped sums for one book" do
    book = create(:business, :personal)
    account = create(:account, business: book)
    groceries = create(:category, business: book, name: "Groceries")
    create(:transaction, account: account, category: groceries, amount_cents: -1_000, posted_on: Date.new(2026, 1, 5))
    create(:transaction, account: account, category: groceries, amount_cents: -2_000, posted_on: Date.new(2026, 1, 20))
    create(:transaction, account: account, category: groceries, amount_cents: -9_000, posted_on: Date.new(2026, 1, 21), transfer: false, excluded: true)
    rows = described_class.load(business_id: book.id, range: Date.new(2026, 1, 1)..Date.new(2026, 1, 31))
    expect(rows).to eq([ described_class::Row.new(month: "2026-01", category_name: "Groceries", kind: "expense", sum_cents: -3_000) ])
  end
end
```

`spec/requests/spending_reports_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Spending report" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:book) { PersonalBookProvisioner.call(household) }

  before do
    create(:transaction, account: create(:account, business: book), category: book.categories.find_by!(name: "Groceries"),
                         amount_cents: -4_200, posted_on: Date.current)
  end

  it "shows the grid and exports CSV" do
    sign_in_as owner
    get business_spending_report_path(book)
    expect(response.body).to include("Groceries", "$42.00")
    get business_spending_report_path(book, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Groceries")
  end

  it "is not found for non-members and on business books" do
    business = create(:business)
    sign_in_as user_with_role("owner", business)
    get business_spending_report_path(book)
    expect(response).to have_http_status(:not_found)
    get business_spending_report_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/reports/spending_spec.rb spec/requests/spending_reports_spec.rb`
Expected: FAIL (`uninitialized constant Reports::Spending`).

- [ ] **Step 3: Implement the report**

`app/models/reports/spending.rb`:

```ruby
module Reports
  # Month × category grid for the personal book. Expenses display as positive (negated sum), per parent spec §3.
  class Spending
    Row = Data.define(:month, :category_name, :kind, :sum_cents)
    Line = Data.define(:name, :amounts, :total_cents)
    MONTH_SQL = "strftime('%Y-%m', transactions.posted_on)".freeze

    attr_reader :months, :income_lines, :expense_lines, :income_total, :expense_total, :net

    def self.months_in(range)
      first = range.first.beginning_of_month
      (0..).lazy.map { first >> _1 }.take_while { _1 <= range.last }.map { _1.strftime("%Y-%m") }.to_a
    end

    def self.load(business_id:, range:)
      Transaction.countable.for_businesses(business_id).where(posted_on: range).joins(:category)
        .group("categories.name", "categories.kind", Arel.sql(MONTH_SQL)).sum("transactions.amount_cents")
        .map { |(name, kind, month), sum| Row.new(month: month, category_name: name, kind: kind, sum_cents: sum) }
    end

    def initialize(rows, months:)
      @months = months
      @income_lines = lines(rows.select { _1.kind == "income" }, sign: 1)
      @expense_lines = lines(rows.select { _1.kind == "expense" }, sign: -1)
      @income_total = total("Total income", @income_lines)
      @expense_total = total("Total spending", @expense_lines)
      @net = line("Net", months.index_with { @income_total.amounts[_1] - @expense_total.amounts[_1] })
    end

    private

    def lines(rows, sign:)
      rows.group_by(&:category_name).sort.map do |name, list|
        line(name, months.index_with { |month| sign * list.select { _1.month == month }.sum(&:sum_cents) })
      end
    end

    def total(name, lines) = line(name, months.index_with { |month| lines.sum { _1.amounts[month] } })

    def line(name, amounts) = Line.new(name: name, amounts: amounts, total_cents: amounts.values.sum)
  end
end
```

`app/models/reports/spending_csv.rb`:

```ruby
require "csv"

module Reports
  module SpendingCsv
    def self.generate(report)
      CSV.generate do |csv|
        csv << [ "Category", *report.months, "Total" ]
        [ *report.income_lines, report.income_total, *report.expense_lines, report.expense_total, report.net ].each do |line|
          csv << [ CsvSafe.text(line.name), *report.months.map { Money.new(line.amounts[_1]).to_input }, Money.new(line.total_cents).to_input ]
        end
      end
    end
  end
end
```

- [ ] **Step 4: Route, controller, view, nav**

`config/routes.rb`, inside `resources :businesses do` next to the other reports:

```ruby
    get "reports/spending", to: "spending_reports#show", as: :spending_report
```

`app/controllers/spending_reports_controller.rb`:

```ruby
class SpendingReportsController < ApplicationController
  include BusinessScoped
  include PersonalOnly
  include DateRangeParams

  def show
    @report = Reports::Spending.new(Reports::Spending.load(business_id: @business.id, range: date_range),
                                    months: Reports::Spending.months_in(date_range))
    respond_to do |format|
      format.html { @uncategorized_count = Transaction.for_businesses(@business.id).inbox.where(posted_on: date_range).count }
      format.csv do
        send_data Reports::SpendingCsv.generate(@report), filename: "spending-#{date_range.first}-#{date_range.last}.csv", type: "text/csv"
      end
    end
  end
end
```

`app/views/spending_reports/show.html.erb`:

```erb
<%= business_nav @business %>
<h1>Spending</h1>
<%= render "shared/date_range_form", url: business_spending_report_path(@business) %>
<%= render "shared/uncategorized_notice", count: @uncategorized_count, inbox_path: business_inbox_path(@business) %>
<p><%= link_to "Download CSV", business_spending_report_path(@business, format: :csv, from: date_range.first, to: date_range.last) %></p>
<table>
  <thead>
    <tr><th>Category</th><% @report.months.each do |month| %><th class="num"><%= month %></th><% end %><th class="num">Total</th></tr>
  </thead>
  <tbody>
    <% [ [ "Income", @report.income_lines, @report.income_total ], [ "Spending", @report.expense_lines, @report.expense_total ] ].each do |heading, lines, total| %>
      <tr><th colspan="<%= @report.months.size + 2 %>"><%= heading %></th></tr>
      <% lines.each do |line| %>
        <tr><td><%= line.name %></td><% @report.months.each do |month| %><td class="num"><%= money(line.amounts[month]) %></td><% end %><td class="num"><%= money(line.total_cents) %></td></tr>
      <% end %>
      <tr><th><%= total.name %></th><% @report.months.each do |month| %><th class="num"><%= money(total.amounts[month]) %></th><% end %><th class="num"><%= money(total.total_cents) %></th></tr>
    <% end %>
    <tr><th><%= @report.net.name %></th><% @report.months.each do |month| %><th class="num"><%= money(@report.net.amounts[month]) %></th><% end %><th class="num"><%= money(@report.net.total_cents) %></th></tr>
  </tbody>
</table>
```

`app/views/businesses/_nav.html.erb`: inside the `if business.personal?` block from Task 7, after Tithe:

```erb
      <li><%= link_to "Spending", business_spending_report_path(business) %></li>
```

- [ ] **Step 5: Run the specs and the suite**

Run: `bundle exec rspec spec/models/reports/spending_spec.rb spec/requests/spending_reports_spec.rb` → PASS. `bundle exec rspec` → 0 failures. `bin/rubocop`, `bin/brakeman --no-pager -q` → clean.

- [ ] **Step 6: Commit**

```bash
git add app config spec
git commit -m "Personal book: month-by-category spending report with CSV"
```

---

### Task 9: Demo data

**Files:**
- Modify: `lib/demo_seeder.rb`, `spec/lib/demo_seeder_spec.rb`

**Interfaces:**
- Consumes: `PersonalBookProvisioner.call`, `Tithe.ledger_for`, `Tithe::Ledger.week_start` (Tasks 2–4).
- Produces: a demo personal book named "Personal" with a "Joint Checking" CSV account, a "GRACE CHURCH" → Tithe rule, `tithe_start_on` = the first Sunday on or after 12 months before `today`, and a balance 1–3 weeks behind.

- [ ] **Step 1: Write the failing spec**

In `spec/lib/demo_seeder_spec.rb`, update the first example: `expect(Business.business_kind.pluck(:name)).to contain_exactly("Pat Consulting", "Jordan Design Studio")` and `expect(Rule.count).to eq(5)`. Then add:

```ruby
  it "seeds a personal book that is a week or three behind on tithe, hidden from the accountant" do
    run
    book = Business.personal.sole
    pat, jordan, accountant = %w[pat jordan accountant].map { User.find_by!(email_address: "#{_1}@example.com") }
    expect(pat.membership_for(book)).to be_owner
    expect(jordan.membership_for(book)).to be_editor
    expect(accountant.membership_for(book)).to be_nil
    expect(book.tithe_start_on).to be_sunday
    ledger = Tithe.ledger_for(book, today: today)
    expect(ledger.balance_cents).to be_between(15_000, 45_000)
    expect(ledger.paid_cents).to be > 0
    expect(book.transactions.where(transfer: true)).to exist
    expect(book.transactions.joins(:category).where(categories: { tithable: false })).to exist
  end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb`
Expected: FAIL (`Business.personal.sole` finds none; rule count 4).

- [ ] **Step 3: Implement**

`lib/demo_seeder.rb#build`: append `seed_personal(household)` after the two `seed_invoices` calls. Add the method (private, after `seed_invoices`):

```ruby
  # Weekly owner draws (tithable), groceries, monthly utilities and refunds (not tithable), a savings transfer,
  # and Grace Church checks every other week that stop two weeks short of today, so the household is a little behind.
  def seed_personal(household)
    book = PersonalBookProvisioner.call(household)
    start = @today << 12
    start += (7 - start.wday) % 7
    book.update!(tithe_start_on: start)
    checking = book.accounts.create!(
      name: "Joint Checking", source: "csv", kind: "checking",
      csv_mapping: CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount").to_h
    )
    categories = book.categories.index_by(&:name)
    tithe_rule = book.rules.create!(field: "payee", operator: "contains", value: "GRACE CHURCH", outcome: "categorize",
                                    category: categories.fetch("Tithe"))

    sequence = 0
    add = lambda do |date, payee, cents, category, **extra|
      next if date > @today

      sequence += 1
      attrs = { posted_on: date, payee: payee, amount_cents: cents, external_id: "demo-personal-#{sequence}" }
      attrs.merge!(category: categories.fetch(category), categorized_by: "user") if category
      checking.transactions.create!(attrs.merge(extra))
    end

    sundays = start.step(@today, 7).to_a
    sundays.each_with_index do |sunday, i|
      add.(sunday + 1, "KROGER", -(9_000 + @random.rand(6_000)), "Groceries")
      add.(sunday + 5, "TRANSFER FROM PAT CONSULTING", 150_000, "Owner draws")
      if i.odd? && i <= sundays.size - 3
        add.(sunday + 9, "CHECK #{1000 + i} GRACE CHURCH", -30_000, "Tithe", rule: tithe_rule, categorized_by: "rule")
      end
    end
    12.downto(0) do |months_ago|
      month = (@today << months_ago).beginning_of_month
      add.(month + 14, "NASHVILLE ELECTRIC", -(11_000 + @random.rand(5_000)), "Utilities")
      add.(month + 20, "AMAZON REFUND", 2_500 + @random.rand(3_000), "Refunds and reimbursements")
    end
    add.(@today - 40, "TRANSFER FROM SAVINGS", 200_000, nil, transfer: true, categorized_by: "rule")
  end
```

Why 1–3 weeks: the last paid odd week is `sundays.size - 3` or `- 4`, each check covers its week and the one before, and the current week's Friday draw may not have happened yet, so 1 to 3 weeks of $150 remain owed.

- [ ] **Step 4: Run the spec and the suite**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb` → PASS. `bundle exec rspec` → 0 failures. `bin/rubocop` → clean.
Run: `bin/rails demo:reset` in development and confirm it prints the logins with no errors.

- [ ] **Step 5: Commit**

```bash
git add lib spec
git commit -m "Demo: personal book with joint checking and a tithe a little behind"
```

---

### Task 10: End-to-end check, docs, PR

**Files:**
- Create: `spec/system/personal_tithe_spec.rb`, `spec/fixtures/files/joint_checking.csv`
- Modify: `README.md`

- [ ] **Step 1: Write the system spec**

`spec/fixtures/files/joint_checking.csv`:

```
Date,Description,Amount
01/09/2026,TRANSFER FROM PAT CONSULTING,"1,500.00"
01/13/2026,CHECK 1042 GRACE CHURCH,-100.00
01/14/2026,KROGER,-82.15
```

`spec/system/personal_tithe_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Personal tithe" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:book) { PersonalBookProvisioner.call(household) }
  let!(:account) { create(:account, :csv, business: book, name: "Joint Checking") }
  let!(:rule) { create(:rule, business: book, value: "grace church", category: book.categories.find_by!(name: "Tithe")) }

  it "imports the joint account, recognizes the tithe check, and shows the balance" do
    system_sign_in_as owner
    visit business_accounts_path(book)
    click_on "Import CSV"
    attach_file "csv_import[file]", Rails.root.join("spec/fixtures/files/joint_checking.csv")
    click_on "Upload"
    select "Date", from: "Date column"
    select "Description", from: "Payee column"
    select "Amount", from: "Amount column"
    select "MM/DD/YYYY", from: "Date format"
    click_on "Save mapping"
    click_on "Import"
    expect(page).to have_content("Imported 3 new transactions")
    expect(account.transactions.find_by!(payee: "CHECK 1042 GRACE CHURCH").category.name).to eq("Tithe")

    visit business_tithe_path(book)
    fill_in "Track tithe from", with: "2026-01-04"
    click_on "Save"
    expect(page).to have_content("Behind $50.00")
  end
end
```

Run: `bundle exec rspec spec/system/personal_tithe_spec.rb` → PASS.

- [ ] **Step 2: README**

In `README.md`, where features are listed (next to the Invoices mention), add a short paragraph: the household owner can set up a **Personal** book from the dashboard for the joint checking account; it has its own categories, rules, inbox, a spending report, and a weekly tithe page (10% of tithable deposits, Sunday–Saturday, payments applied oldest week first). Only the household owner and linked spouse can see it; the accountant cannot.

- [ ] **Step 3: Full verification**

Run each and confirm clean output:
- `bundle exec rspec` → all examples, 0 failures, nothing else printed
- `bin/rubocop`
- `bin/brakeman --no-pager`
- `bin/bundler-audit`
- `bin/importmap audit`

- [ ] **Step 4: Commit, push, open the stacked PR**

```bash
git add spec README.md
git commit -m "Personal tithe: end-to-end spec and README"
git push -u origin tithing
gh pr create --base invoices --title "Personal book + tithing (sub-project 3)" --body-file <body>
```

The PR body has: Summary (what the personal book and tithe page do, the stacking on #6), the spec and plan paths, and **Acceptance testing** steps (below), ending with the attribution lines from Global Constraints' PR format:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01VdQWdubZ6L19ekyi7gz8GK
```

Acceptance testing (put the same steps in the PR body and the GB-9 Kaneo task description):

1. `bin/rails demo:reset`, `bin/dev`; log in as `pat@example.com` (password and TOTP secret printed by the reset).
2. Dashboard: a "Personal" section with "Tithe: Behind $…" (between $150 and $450). Site nav has "Personal".
3. Personal → Tithe: weekly rows newest first; the newest one to three weeks are open/partial; expanding a week lists its draws and Grace Church checks; "Download CSV" downloads a weekly CSV.
4. Change "Track tithe from" to a later Sunday → the balance changes; type a future date → error flash; clear it → prompt shown.
5. Personal → Categories: Tithe shows "Tithe payment", Refunds "Not tithable"; create an expense category with "Tithe payment" checked; no Schedule C picker.
6. Personal → Transactions: recategorize a Grace Church check as Groceries → Tithe balance rises by that amount; mark an owner draw as a transfer → owed drops by 10% of it.
7. Personal → Spending: month × category grid; CSV download.
8. Personal nav has no Mileage, Invoices, Clients, P&L, Schedule C, or Aging; visiting `/businesses/<personal id>/invoices` → 404.
9. Log in as `jordan@example.com`: Personal is visible and editable, but no start-date form on Tithe.
10. Log in as `accountant@example.com`: no Personal in nav or dashboard; `/businesses/<personal id>` → 404; Household P&L and transaction export contain no personal rows (no KROGER, no Groceries).
11. As Pat, Invites → New: the Personal book is not offered.

- [ ] **Step 5: Get CI green and update Kaneo**

Watch `gh pr checks --watch`; fix anything red. Then move GB-9 to In Review with a comment linking the PR, and put the acceptance steps in its description.

---

## Summary

| Task | Delivers |
|---|---|
| 1 | `Business` kind/`tithe_start_on`, category `tithable`/`tithe`, personal template |
| 2 | Provisioning, owner/spouse memberships, nav + dashboard entry |
| 3 | Pure `Tithe::Ledger` (weeks, rounding, FIFO, balance, YTD) |
| 4 | `Tithe::Entries` classification + `Tithe.ledger_for` |
| 5 | Business-only 404s, personal nav/overview/categories, CSV deductible fix |
| 6 | Household/access/invite/dashboard exclusions |
| 7 | Tithe page, start date, CSV, dashboard balance |
| 8 | Spending report + CSV |
| 9 | Demo data |
| 10 | System spec, README, verification, stacked PR, acceptance steps |
