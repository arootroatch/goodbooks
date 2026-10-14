# goodbooks Goals (Sub-project 8) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every book gets goals. **Payment goals** sum the outflows linked to them; links come from a rule-style matcher on the goal, and can be added or removed by hand. **Savings goals** share an account's balance in priority order (a live waterfall). There is a widget on the book overview and in the dashboard's Personal section, plus a per-goal report. Accounts gain balances: bank-reported for Plaid, opening balance + later transactions for manual/CSV.

**Architecture:**
- `Goal` (per book, ordered like `Rule`) carries its own matcher fields, evaluated by the existing `RuleEngine` through a `Goal::MatcherRule` value object.
- `GoalMatcher` links eligible transactions (`transactions.goal_id` + `goal_linked_by`). It runs wherever new transactions enter the books, and re-runs book-wide (`rematch`) whenever a payments goal's matcher, order, or archive state changes.
- `Goals::Progress` computes saved amounts on read, with no caching.
- `Account#balance_cents` reads Plaid's reported balance (stored by `PlaidFeed::Sync` from the `accounts` array `/transactions/sync` already returns) or opening balance + later transactions.

**Tech Stack:** Ruby 4.0.7, Rails 8.1.4, SQLite, Hotwire (Turbo + Stimulus via importmap, SortableJS), RSpec, FactoryBot, Capybara (rack_test + headless Chrome), WebMock, Brakeman, bundler-audit, RuboCop (rails-omakase).

**Spec:** `docs/superpowers/specs/2026-10-14-goodbooks-goals-design.md` (parent: `docs/superpowers/specs/2026-10-05-goodbooks-design.md` §3 cross-cutting rules; builds on the Personal book and Plaid specs).

## Prerequisites (before Task 1)

- `export PATH="$HOME/.rubies/ruby-4.0.7/bin:$PATH"` before every command (`ruby -v` → `ruby 4.0.7`).
- Work on branch `goals`, cut from `main`. It already holds the spec commit. Run `bundle install` once.
- **Parallel branch:** `tax-engine` (PR #13) is open against `main`. Both touch `db/schema.rb`, `app/models/transaction.rb`, `app/views/layouts/_sidebar.html.erb`, `app/views/dashboards/show.html.erb`, `app/controllers/dashboards_controller.rb`, `lib/demo_seeder.rb`, `spec/lib/demo_seeder_spec.rb`, and `docs/roadmap.md`. Keep every change to those files small and additive: new lines, new partials, new methods, no reformatting or reordering. Goals migrations use the version prefix `2026101400000…`; tax engine's use `20261012…`. Whichever PR merges second rebases. For `db/schema.rb`, re-run `bin/rails db:migrate` and commit the regenerated file.
- `bin/rails db:test:prepare && bundle exec rspec`. Record the example count; it must be `0 failures` with no other output. This is the baseline. If it is not green, stop and report.

## Global Constraints

- Money is signed integer cents in `*_cents` columns, shown with `money(cents)` and entered through `money_attribute`. Never floats: Plaid balances are converted with `(BigDecimal(value.to_s) * 100).round.to_i`.
- `Transaction#amount_cents`: positive means money into the account. Payment goals count **outflows** (`amount_cents < 0`), and saved = −Σ amount of linked, non-excluded rows, floored at 0.
- A transaction belongs to at most one goal. `goal_linked_by` is `"matcher"`, `"user"`, or nil. `goal_id: nil, goal_linked_by: "user"` is a hand unlink, and the matcher never touches such a row. The matcher never touches rows linked by `"user"`.
- Goals never change categorization. `GoalMatcher` writes only `goal_id`, `goal_linked_by` and `updated_at` (via `update_columns`).
- A goal's kind can't change after creation.
- Never name an association, method, or local `transaction`. DB transactions use `ApplicationRecord.transaction`. Use `txn` for locals.
- Authorization:
  - Non-member → 404 (lookups through `Current.user.accessible_businesses`, i.e. `BusinessScoped`).
  - Viewer writing → 403 (`require_editor!`).
  - Cross-book goal, account, or transaction ids → 404 (found through `@business`) or a validation error (the model checks the book).
- `config.action_controller.raise_on_missing_callback_actions = true` in test: every `only:`/`except:` list must name existing actions.
- Test output must stay clean: a passing `bundle exec rspec` prints only the reporter.
- TDD: each task writes its failing spec first and runs it to see it fail.
- Formatting: rails-omakase (`[ a, b ]` with inner spaces, double quotes). `bin/rubocop` must pass after every task. `bin/brakeman --no-pager -q` must report no warnings after Tasks 7 and 8.
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- Kaneo: the controlling session (not task implementers) comments progress on GB-11 ("Phase 8: Goals", task id `j395uiqqya5vvrb7exspf2vo`, project GoodBooks, workspace Root User Projects) after each task, and moves it to In Review when the PR opens.

## Review Focus

1. **Priority between overlapping payment goals.** Two goals both match "TONY", and the user drags the second above the first. Every matcher-linked row moves to the new top goal; hand-linked rows stay where they are. (Pinned in Task 4: `move_to!` rematches.)
2. **Archiving a goal keeps its history.** Archiving a payment goal must not unlink its rows, and its report still lists them. Unarchiving re-runs the matcher without duplicating anything. (Pinned in Task 4.)
3. **Balance edges.**
   - A transaction posted *on* `opening_balance_on` is already in the opening balance and must not count again.
   - An excluded row never counts.
   - A negative balance fills nothing.
   - A Plaid account that hasn't synced since this shipped shows "unknown", not $0.
   (Pinned in Tasks 1 and 6.)
4. **Crafted writes.**
   - A goal pointing at another book's account, or at a credit or archived account.
   - A transaction linked to another book's goal or to a savings goal.
   - An unlink of a transaction from another book.
   - A viewer trying any write.
   All are rejected, and nothing changes. (Pinned in Tasks 3, 7 and 8.)
5. **Old Plaid pages without `accounts`.** A page lacking the key leaves stored balances unchanged, and only the *last* page's balances are written. (Pinned in Task 2.)

## Spec decisions made while planning

- **Rematching is book-wide** (`GoalMatcher#rematch`, no argument; spec: `rematch(goal)`). It clears every *active* payments goal's `matcher` links in the book, then matches all eligible rows again. Correct priority after a reorder needs exactly that, and it costs one pass over a household-sized book. Archived goals' links are never cleared.
- `Goal` runs `rematch` from an `after_save` callback, inside the save's DB transaction. It fires on create, on a matcher change, and on `archived_at` changing. `move_to!` (which uses `update_all`) calls it explicitly. The callback stores the number of rows linked in `Goal#rematched_count`, for the controller's flash.
- `Goals::Progress.for_goals(goals)` waterfalls only the active savings goals it is given. `Goals::Progress.for_book(book)` passes every active goal of the book, which is what every page uses.
- The savings report's running balance comes from `Goals::BalanceHistory.for(account, today:)`.
- The Archive/Unarchive buttons reuse the `Archiving` concern. A goal's update goes through `record.update`, which fires the rematch callback.
- Delete is offered on the edit page with a confirm. Archive is the usual path.

## File structure

| File | Responsibility |
|---|---|
| `db/migrate/20261014000001_add_balances_to_accounts.rb` | opening + reported balance columns |
| `db/migrate/20261014000002_create_goals.rb` | `goals` table |
| `db/migrate/20261014000003_add_goal_to_transactions.rb` | `goal_id`, `goal_linked_by` |
| `app/models/account.rb` | `money_attribute :opening_balance`, pair validation, `balance_cents`, `has_many :goals` |
| `app/models/goal.rb` | validations, ordering, `MatcherRule`, rematch callback, destroy cleanup |
| `app/models/business.rb` | `has_many :goals` |
| `app/models/transaction.rb` | `belongs_to :goal`, link validations |
| `app/services/goal_matcher.rb` | `apply(transactions)`, `rematch` |
| `app/models/goals/progress.rb` | saved amounts, waterfall |
| `app/models/goals/balance_history.rb` | running balance rows for the savings report |
| `app/models/plaid_gateway.rb`, `lib/fake_plaid_gateway.rb` | `accounts:` balances on each sync page |
| `app/services/plaid_feed/sync.rb` | store balances; call `GoalMatcher` |
| `app/models/csv_import.rb`, `app/controllers/transactions_controller.rb` | call `GoalMatcher`; goal select |
| `app/controllers/goals_controller.rb` | index, show, new, create, edit, update, destroy, move, archive, unarchive |
| `app/controllers/goal_links_controller.rb` | destroy (unlink) |
| `app/views/goals/*` | index, show, new, edit, `_form`, `_bar`, `_widget` |
| `app/javascript/controllers/goal_kind_controller.js` | show the matcher or account fields for the chosen kind |
| `app/assets/stylesheets/components/goals.css` | progress bar and widget |
| `app/models/household_dashboard.rb`, `app/views/dashboards/show.html.erb` | personal goals widget |
| `app/controllers/businesses_controller.rb`, `app/views/businesses/show.html.erb` | book goals widget |
| `lib/demo_seeder.rb` | demo goals |

---

### Task 1: Account balances (opening balance for manual/CSV; Balance column)

**Files:**
- Create: `db/migrate/20261014000001_add_balances_to_accounts.rb`
- Modify: `app/models/account.rb`, `app/controllers/accounts_controller.rb`, `app/views/accounts/_form.html.erb`, `app/views/accounts/index.html.erb`
- Test: `spec/models/account_balance_spec.rb`, `spec/requests/accounts_spec.rb`

**Interfaces:**
- Produces:
  - `Account#balance_cents → Integer | nil` and `Account#balance_known? → Boolean`
  - `Account#opening_balance` / `#opening_balance=` (money input)
  - columns `opening_balance_cents`, `opening_balance_on`, `reported_balance_cents`, `balance_reported_at`

- [ ] **Step 1: Write the failing model spec**

`spec/models/account_balance_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Account, "balances" do
  let(:account) { create(:account, opening_balance: "1,000.00", opening_balance_on: Date.new(2026, 1, 31)) }

  it "is unknown without an opening balance" do
    expect(create(:account).balance_cents).to be_nil
    expect(create(:account)).not_to be_balance_known
  end

  it "adds non-excluded transactions posted after the opening date" do
    create(:transaction, account: account, posted_on: Date.new(2026, 1, 31), amount_cents: -999_99)
    create(:transaction, account: account, posted_on: Date.new(2026, 2, 1), amount_cents: -250_00)
    create(:transaction, account: account, posted_on: Date.new(2026, 2, 2), amount_cents: 50_00)
    create(:transaction, account: account, posted_on: Date.new(2026, 2, 3), amount_cents: -10_00, excluded: true)
    create(:transaction, account: account, posted_on: Date.new(2026, 2, 4), amount_cents: -100_00, transfer: true)
    expect(account.balance_cents).to eq(1_000_00 - 250_00 + 50_00 - 100_00)
    expect(account).to be_balance_known
  end

  it "uses the reported balance for Plaid accounts and ignores transactions" do
    plaid = create(:account, :plaid)
    expect(plaid.balance_cents).to be_nil
    plaid.update!(reported_balance_cents: 4_321_00, balance_reported_at: Time.current)
    create(:transaction, account: plaid, amount_cents: -5_00)
    expect(plaid.balance_cents).to eq(4_321_00)
  end

  it "requires the opening amount and date together" do
    expect(build(:account, opening_balance: "10", opening_balance_on: nil)).to have_error_on(:opening_balance_on)
    expect(build(:account, opening_balance: "", opening_balance_on: Date.current)).to have_error_on(:opening_balance)
    expect(build(:account, opening_balance: "abc", opening_balance_on: Date.current)).not_to be_valid
    expect(build(:account, opening_balance: "-25.00", opening_balance_on: Date.current)).to be_valid
  end

  def have_error_on(attr) = satisfy { |record| !record.valid? && record.errors[attr].any? }
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/models/account_balance_spec.rb`
Expected: FAIL with `NoMethodError: undefined method 'opening_balance='`.

- [ ] **Step 3: Migration**

`db/migrate/20261014000001_add_balances_to_accounts.rb`:

```ruby
class AddBalancesToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :opening_balance_cents, :integer
    add_column :accounts, :opening_balance_on, :date
    add_column :accounts, :reported_balance_cents, :integer
    add_column :accounts, :balance_reported_at, :datetime
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 4: Model**

In `app/models/account.rb`:
- add `include MoneyAttribute` as the first line of the class body
- add `money_attribute :opening_balance, allow_blank: true` after the enums
- add `validate :opening_balance_complete` after the existing `validate :plaid_link_complete`
- add the public methods below after `csv_importable?`, and the private method under `private`

```ruby
  # Plaid: what the bank reported at the last sync. Manual/CSV: the opening balance plus every non-excluded
  # transaction after its date (rows on the date are already in it). Nil when unknown.
  def balance_cents
    return reported_balance_cents if plaid?
    return if opening_balance_cents.nil? || opening_balance_on.nil?

    opening_balance_cents + transactions.where(excluded: false).where("posted_on > ?", opening_balance_on).sum(:amount_cents)
  end

  def balance_known? = !balance_cents.nil?
```

```ruby
  def opening_balance_complete
    return if errors[:opening_balance].any?

    if opening_balance_cents && opening_balance_on.nil?
      errors.add(:opening_balance_on, "can't be blank with an opening balance")
    elsif opening_balance_cents.nil? && opening_balance_on
      errors.add(:opening_balance, "can't be blank with an as-of date")
    end
  end
```

- [ ] **Step 5: Run the model spec**

Run: `bundle exec rspec spec/models/account_balance_spec.rb`
Expected: PASS.

- [ ] **Step 6: Write the failing request spec**

Append to `spec/requests/accounts_spec.rb`, inside the top-level `describe`. If its local `let`s differ, create `business` the same way the file's other examples do.

```ruby
  describe "balances" do
    let!(:book) { create(:business) }

    it "lets the owner set an opening balance on a manual account and shows the balance" do
      account = create(:account, business: book, name: "Savings", kind: "savings")
      sign_in_as user_with_role("owner", book)
      patch business_account_path(book, account), params: { account: { name: "Savings", kind: "savings",
                                                                        opening_balance: "8,000.00", opening_balance_on: "2026-01-01" } }
      expect(account.reload).to have_attributes(opening_balance_cents: 8_000_00, opening_balance_on: Date.new(2026, 1, 1))
      get business_accounts_path(book)
      expect(Nokogiri::HTML(response.body).at_css("##{ActionView::RecordIdentifier.dom_id(account)} td.balance").text).to include("$8,000.00")
    end

    it "does not accept an opening balance for a Plaid account and shows its reported balance read-only" do
      account = create(:account, :plaid, business: book, reported_balance_cents: 12_34, balance_reported_at: 1.hour.ago)
      sign_in_as user_with_role("owner", book)
      patch business_account_path(book, account), params: { account: { name: account.name, kind: "checking",
                                                                        opening_balance: "5", opening_balance_on: "2026-01-01" } }
      expect(account.reload.opening_balance_cents).to be_nil
      get edit_business_account_path(book, account)
      expect(response.body).to include("$12.34").and include("reported about 1 hour ago")
      expect(response.body).not_to include("account[opening_balance]")
    end
  end
```

- [ ] **Step 7: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/accounts_spec.rb -e balances`
Expected: FAIL (the opening balance isn't permitted; there's no `td.balance`).

- [ ] **Step 8: Controller and views**

In `app/controllers/accounts_controller.rb`:
- add `BALANCE_FIELDS = %i[opening_balance opening_balance_on].freeze` under `CREATABLE_SOURCES`
- in `create`, change the permit to `params.expect(account: %i[name source kind] + BALANCE_FIELDS)`
- in `update`, replace the permit with:

```ruby
    fields = @account.plaid? ? %i[name kind] : %i[name kind] + BALANCE_FIELDS
    if @account.update(params.expect(account: fields))
```

`app/views/accounts/_form.html.erb`: insert before `<%= f.submit %>`:

```erb
  <% if account.plaid? %>
    <p>Balance <%= money(account.balance_cents) %>
      <% if account.balance_reported_at %><span class="muted">· reported <%= time_ago_in_words(account.balance_reported_at) %> ago</span><% end %></p>
  <% else %>
    <p>
      <%= f.label :opening_balance %> <%= f.text_field :opening_balance, size: 12, inputmode: "decimal", placeholder: "optional" %>
      <%= f.label :opening_balance_on, "as of" %> <%= f.date_field :opening_balance_on %>
      <small>the balance at the end of that day; later transactions are added to it</small>
    </p>
  <% end %>
```

`app/views/accounts/index.html.erb`:
- header row: `<thead><tr><th>Name</th><th>Source</th><th>Kind</th><th class="num">Balance</th><th></th></tr></thead>`
- add after the kind cell: `<td class="num balance"><%= money(account.balance_cents) %></td>`

- [ ] **Step 9: Run the specs, rubocop, commit**

Run: `bundle exec rspec spec/models/account_balance_spec.rb spec/requests/accounts_spec.rb spec/models/account_plaid_spec.rb && bin/rubocop`
Expected: PASS, no offenses.

```bash
git add db/migrate/20261014000001_add_balances_to_accounts.rb db/schema.rb app/models/account.rb app/controllers/accounts_controller.rb app/views/accounts spec/models/account_balance_spec.rb spec/requests/accounts_spec.rb
git commit -m "Account balances: opening balance for manual and CSV accounts, reported balance column for Plaid

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Plaid-reported balances on sync

**Files:**
- Modify: `app/models/plaid_gateway.rb`, `lib/fake_plaid_gateway.rb`, `app/services/plaid_feed/sync.rb`
- Test: `spec/models/plaid_gateway_spec.rb`, `spec/lib/fake_plaid_gateway_spec.rb`, `spec/services/plaid_feed/sync_spec.rb`

**Interfaces:**
- Consumes: `accounts.reported_balance_cents`, `accounts.balance_reported_at` (Task 1).
- Produces:
  - Every `transactions_sync` page hash gains `accounts: [ { account_id: String, current_cents: Integer | nil } ]`.
  - `FakePlaidGateway#set_balance(account_id, cents)`.

- [ ] **Step 1: Write the failing specs**

In `spec/models/plaid_gateway_spec.rb`, in the first `transactions_sync` example:
- add to the stubbed body hash: `accounts: [ { account_id: "a1", balances: { current: 1234.56, available: nil } }, { account_id: "a2", balances: { current: nil } } ],`
- add the assertion: `expect(page[:accounts]).to eq([ { account_id: "a1", current_cents: 1_234_56 }, { account_id: "a2", current_cents: nil } ])`

In `spec/lib/fake_plaid_gateway_spec.rb`:
- change the three full-page `eq` expectations in "serves scripted pages…" to include `accounts: []`. For example: `eq(added: [ txn ], modified: [], removed: [], accounts: [], next_cursor: "page-1", has_more: true)`.
- add:

```ruby
  it "reports balances set for accounts on every page" do
    fake.set_balance("fake-savings", 8_000_00)
    expect(fake.transactions_sync("access", nil)[:accounts]).to eq([ { account_id: "fake-savings", current_cents: 8_000_00 } ])
  end
```

In `spec/services/plaid_feed/sync_spec.rb`, add:

```ruby
  describe "balances" do
    it "stores the balances from the last page for assigned, active accounts" do
      archived = create(:account, :plaid, business: book, plaid_item: item, plaid_account_id: "acc-old", archived_at: Time.current)
      plaid_gateway.add_page("access-1", added: [])
      plaid_gateway.add_page("access-1", added: [])
      plaid_gateway.set_balance("acc-checking", 9_876_54)
      plaid_gateway.set_balance("acc-old", 1_00)
      plaid_gateway.set_balance("acc-unassigned", 2_00)
      sync
      expect(checking.reload).to have_attributes(reported_balance_cents: 9_876_54, balance_reported_at: be_present)
      expect(archived.reload.reported_balance_cents).to be_nil
    end

    it "leaves balances alone when a page has no accounts key" do
      checking.update!(reported_balance_cents: 5_00, balance_reported_at: 1.day.ago)
      allow(plaid_gateway).to receive(:transactions_sync).and_return({ added: [], modified: [], removed: [], next_cursor: "c", has_more: false })
      sync
      expect(checking.reload.reported_balance_cents).to eq(5_00)
    end
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bundle exec rspec spec/models/plaid_gateway_spec.rb spec/lib/fake_plaid_gateway_spec.rb spec/services/plaid_feed/sync_spec.rb`
Expected: FAIL (no `accounts` key; `set_balance` undefined).

- [ ] **Step 3: Real gateway**

In `app/models/plaid_gateway.rb` `#transactions_sync`, add to the returned hash after `removed:`:

```ruby
      accounts: Array(response.accounts).map { { account_id: _1.account_id, current_cents: balance_cents(_1.balances&.current) } },
```

and under `private`:

```ruby
  def balance_cents(value) = value.nil? ? nil : (BigDecimal(value.to_s) * 100).round.to_i
```

- [ ] **Step 4: Fake gateway**

In `lib/fake_plaid_gateway.rb`:
- in `initialize`, add `@balances = {}`
- add the public method:

```ruby
  def set_balance(account_id, cents)
    @balances[account_id] = cents
  end
```

- in `transactions_sync`, merge the balances into both branches:

```ruby
      balances = @balances.map { |account_id, cents| { account_id: account_id, current_cents: cents } }
      if index < pages.size
        pages[index].merge(accounts: balances, next_cursor: "page-#{index + 1}", has_more: index + 1 < pages.size)
      else
        EMPTY_PAGE.merge(accounts: balances, next_cursor: cursor.presence || "page-0", has_more: false)
      end
```

(Define `balances` before the `if`, inside the `record` block.)

- [ ] **Step 5: Sync stores the last page's balances**

In `app/services/plaid_feed/sync.rb`:
- `fetch` returns a fifth element. Declare `balances = nil` next to `added, modified, removed = [], [], []`, set `balances = page[:accounts] if page.key?(:accounts)` inside the loop, and return `[ added, modified, removed, cursor, balances ]`.
- In `call`, destructure `added, modified, removed, cursor, balances = fetch`, and after `removed.each { … }` add `store_balances(balances, accounts) if balances`.
- Add the private method:

```ruby
    def store_balances(balances, accounts)
      balances.each do |balance|
        account = accounts[balance[:account_id]]
        account&.update!(reported_balance_cents: balance[:current_cents], balance_reported_at: Time.current)
      end
    end
```

- [ ] **Step 6: Run the specs, rubocop, commit**

Run: `bundle exec rspec spec/models/plaid_gateway_spec.rb spec/lib/fake_plaid_gateway_spec.rb spec/services/plaid_feed spec/jobs/plaid_sync_job_spec.rb && bin/rubocop`
Expected: PASS.

```bash
git add app/models/plaid_gateway.rb lib/fake_plaid_gateway.rb app/services/plaid_feed/sync.rb spec/models/plaid_gateway_spec.rb spec/lib/fake_plaid_gateway_spec.rb spec/services/plaid_feed/sync_spec.rb
git commit -m "Plaid sync stores each account's reported balance

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `Goal` model and transaction goal links

**Files:**
- Create: `db/migrate/20261014000002_create_goals.rb`, `db/migrate/20261014000003_add_goal_to_transactions.rb`, `app/models/goal.rb`, `spec/factories/goals.rb`
- Modify: `app/models/business.rb`, `app/models/account.rb`, `app/models/transaction.rb`
- Test: `spec/models/goal_spec.rb`, `spec/models/transaction_goal_spec.rb`

**Interfaces:**
- Produces:
  - `Goal`: `KINDS = %w[payments savings]`, `scope :active`, `scope :ordered`, `scope :payments`, `scope :savings`; `#payments?`, `#savings?`, `#archived?`, `#matcher?`, `#matcher_rule → Goal::MatcherRule`, `#matcher_description → String`; `money_attribute :target`, `:match_amount_min`, `:match_amount_max`.
  - `Goal::MatcherRule = Data.define(:field, :operator, :value, :amount_min_cents, :amount_max_cents)`, accepted by `RuleEngine.matches?`.
  - `Transaction`: `belongs_to :goal, optional: true`; `GOAL_LINKED_BY = %w[matcher user]`.
  - `Business has_many :goals`; `Account has_many :goals`.
  - Factory `:goal` (payments, matcher `payee contains "tony"`, target $30,000) with trait `:savings` (needs `account:`).

- [ ] **Step 1: Write the failing specs**

`spec/factories/goals.rb`:

```ruby
FactoryBot.define do
  factory :goal do
    business
    sequence(:name) { |n| "Goal #{n}" }
    kind { "payments" }
    target_cents { 30_000_00 }
    match_field { "payee" }
    match_operator { "contains" }
    match_value { "tony" }

    trait :savings do
      kind { "savings" }
      match_field { nil }
      match_operator { nil }
      match_value { nil }
      account { association :account, business: business, kind: "savings" }
    end
  end
end
```

`spec/models/goal_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Goal do
  let(:book) { create(:business) }

  it "requires a name, a known kind and a positive target" do
    expect(build(:goal, business: book, name: "")).not_to be_valid
    expect(build(:goal, business: book, kind: "other")).not_to be_valid
    expect(build(:goal, business: book, target_cents: 0)).not_to be_valid
    expect(build(:goal, business: book, target: "abc")).not_to be_valid
  end

  it "accepts a payment goal with a full matcher or none at all, not a partial one" do
    expect(build(:goal, business: book)).to be_valid
    expect(build(:goal, business: book, match_field: nil, match_operator: nil, match_value: nil)).to be_valid
    expect(build(:goal, business: book, match_value: "")).not_to be_valid
    expect(build(:goal, business: book, match_operator: "regex")).not_to be_valid
    expect(build(:goal, business: book, match_amount_min: "50", match_amount_max: "10")).not_to be_valid
  end

  it "needs an active, non-credit account in the same book for savings" do
    expect(build(:goal, :savings, business: book)).to be_valid
    expect(build(:goal, :savings, business: book, account: nil)).not_to be_valid
    expect(build(:goal, :savings, business: book, account: create(:account))).not_to be_valid
    expect(build(:goal, :savings, business: book, account: create(:account, business: book, kind: "credit"))).not_to be_valid
    expect(build(:goal, :savings, business: book, account: create(:account, business: book, archived_at: Time.current))).not_to be_valid
  end

  it "clears fields that don't belong to its kind" do
    savings = create(:goal, :savings, business: book, match_value: "tony", match_field: "payee", match_operator: "contains")
    expect(savings.attributes.values_at("match_field", "match_operator", "match_value")).to all(be_nil)
    payments = create(:goal, business: book, account: create(:account, business: book))
    expect(payments.account_id).to be_nil
  end

  it "does not let the kind change after creation" do
    goal = create(:goal, business: book)
    expect(goal.update(kind: "savings", account: create(:account, business: book))).to be(false)
    expect(goal.errors[:kind]).to be_present
  end

  it "positions new goals last and orders by position" do
    first = create(:goal, business: book)
    second = create(:goal, business: book)
    expect(book.goals.ordered).to eq([ first, second ])
    expect(second.position).to eq(first.position + 1)
  end

  it "exposes its matcher as a rule RuleEngine understands" do
    goal = build(:goal, business: book, match_value: "Tony", match_amount_max: "2,000")
    expect(goal).to be_matcher
    expect(RuleEngine.matches?(goal.matcher_rule, { payee: "ZELLE TONY RUSSO", memo: nil, amount_cents: -1_500_00 })).to be(true)
    expect(RuleEngine.matches?(goal.matcher_rule, { payee: "ZELLE TONY RUSSO", memo: nil, amount_cents: -2_500_00 })).to be(false)
    expect(goal.matcher_description).to eq("payee contains \"Tony\" · ≤ $2,000.00")
    expect(build(:goal, business: book, match_field: nil, match_operator: nil, match_value: nil)).not_to be_matcher
  end
end
```

`spec/models/transaction_goal_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Transaction, "goal links" do
  let(:book) { create(:business) }
  let(:txn) { create(:transaction, account: create(:account, business: book)) }

  it "links to a payment goal in its book" do
    goal = create(:goal, business: book)
    expect(txn.update(goal: goal, goal_linked_by: "user")).to be(true)
  end

  it "rejects another book's goal, a savings goal, and unknown link sources" do
    expect(txn.update(goal: create(:goal))).to be(false)
    expect(txn.errors[:goal]).to be_present
    expect(txn.update(goal: create(:goal, :savings, business: book))).to be(false)
    expect(txn.reload.update(goal_linked_by: "robot")).to be(false)
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bundle exec rspec spec/models/goal_spec.rb spec/models/transaction_goal_spec.rb`
Expected: FAIL with `NameError: uninitialized constant Goal`.

- [ ] **Step 3: Migrations**

`db/migrate/20261014000002_create_goals.rb`:

```ruby
class CreateGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :goals do |t|
      t.references :business, null: false, foreign_key: true
      t.references :account, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.integer :target_cents, null: false
      t.integer :position, null: false
      t.date :target_date
      t.datetime :archived_at
      t.string :match_field
      t.string :match_operator
      t.string :match_value
      t.integer :match_amount_min_cents
      t.integer :match_amount_max_cents
      t.timestamps
    end
  end
end
```

`db/migrate/20261014000003_add_goal_to_transactions.rb`:

```ruby
class AddGoalToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :transactions, :goal, foreign_key: true
    add_column :transactions, :goal_linked_by, :string
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 4: Model**

`app/models/goal.rb`:

```ruby
# A money goal in one book. Payment goals add up the outflows linked to them (by their matcher or by hand);
# savings goals share their account's balance with the book's other savings goals on it, in position order.
class Goal < ApplicationRecord
  include MoneyAttribute

  KINDS = %w[payments savings].freeze
  MatcherRule = Data.define(:field, :operator, :value, :amount_min_cents, :amount_max_cents)

  money_attribute :target
  money_attribute :match_amount_min, allow_blank: true
  money_attribute :match_amount_max, allow_blank: true

  belongs_to :business
  belongs_to :account, optional: true
  has_many :transactions, dependent: nil

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }
  scope :payments, -> { where(kind: "payments") }
  scope :savings, -> { where(kind: "savings") }

  validates :name, presence: true, length: { maximum: 100 }
  validates :kind, inclusion: { in: KINDS }
  validates :target_cents, numericality: { greater_than: 0 }, if: -> { errors[:target].empty? && target_cents }
  validates :match_field, inclusion: { in: Rule::FIELDS }, allow_nil: true
  validates :match_operator, inclusion: { in: Rule::OPERATORS }, allow_nil: true
  validates :match_value, length: { maximum: 100 }
  validates :match_amount_min_cents, :match_amount_max_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :matcher_complete
  validate :amount_range_ordered
  validate :savings_account_usable
  validate :kind_unchanged, on: :update

  before_validation :clear_other_kind_fields
  before_create { self.position = (business.goals.maximum(:position) || 0) + 1 }

  def payments? = kind == "payments"
  def savings? = kind == "savings"
  def archived? = archived_at.present?
  def archived = archived?

  def matcher? = payments? && match_field.present? && match_operator.present? && match_value.present?

  def matcher_rule
    MatcherRule.new(field: match_field, operator: match_operator, value: match_value,
                    amount_min_cents: match_amount_min_cents, amount_max_cents: match_amount_max_cents)
  end

  def matcher_description
    amounts = [ match_amount_min_cents && "≥ #{Money.new(match_amount_min_cents)}",
                match_amount_max_cents && "≤ #{Money.new(match_amount_max_cents)}" ].compact
    [ "#{match_field} #{match_operator.to_s.humanize(capitalize: false)} \"#{match_value}\"", *amounts ].join(" · ")
  end

  private

  def clear_other_kind_fields
    if savings?
      self.match_field = self.match_operator = self.match_value = nil
      self.match_amount_min_cents = self.match_amount_max_cents = nil
    else
      self.account = nil
      self.match_value = match_value.presence
      self.match_field = match_field.presence
      self.match_operator = match_operator.presence
    end
  end

  def matcher_complete
    return unless payments?

    parts = [ match_field, match_operator, match_value ]
    errors.add(:match_value, "needs a field, an operator and a value") if parts.any?(&:present?) && !parts.all?(&:present?)
  end

  def amount_range_ordered
    return unless match_amount_min_cents && match_amount_max_cents && match_amount_min_cents > match_amount_max_cents

    errors.add(:match_amount_min, "must be less than or equal to the maximum")
  end

  def savings_account_usable
    return unless savings?
    return errors.add(:account, "can't be blank") if account.nil?

    if account.business_id != business_id then errors.add(:account, "must belong to this book")
    elsif account.archived? then errors.add(:account, "is archived")
    elsif account.kind_credit? then errors.add(:account, "can't be a credit account")
    end
  end

  def kind_unchanged
    errors.add(:kind, "can't be changed") if will_save_change_to_kind?
  end
end
```

In `app/models/business.rb`, add next to the other `has_many` lines: `has_many :goals, dependent: :destroy`.
In `app/models/account.rb`, add after `has_many :csv_imports…`: `has_many :goals, dependent: :restrict_with_error`.

In `app/models/transaction.rb`:
- add `GOAL_LINKED_BY = %w[matcher user].freeze` after `CATEGORIZED_BY`
- add `belongs_to :goal, optional: true` after `belongs_to :rule, optional: true`
- add `validates :goal_linked_by, inclusion: { in: GOAL_LINKED_BY }, allow_nil: true` after the `review_reason` validation
- add `validate :goal_in_book` after `validate :category_in_business`
- add under `private`:

```ruby
  def goal_in_book
    return if goal.nil? || account.nil?

    errors.add(:goal, "must be a payment goal in this book") unless goal.payments? && goal.business_id == account.business_id
  end
```

`Business` is destroyed only in specs, and `dependent: :destroy` on goals runs before the transactions' FK matters. Task 4 adds the `before_destroy` that clears links.

- [ ] **Step 5: Run the specs, rubocop, commit**

Run: `bundle exec rspec spec/models/goal_spec.rb spec/models/transaction_goal_spec.rb spec/models/transaction_spec.rb spec/models/business_spec.rb && bin/rubocop`
Expected: PASS.

```bash
git add db/migrate/20261014000002_create_goals.rb db/migrate/20261014000003_add_goal_to_transactions.rb db/schema.rb app/models/goal.rb app/models/business.rb app/models/account.rb app/models/transaction.rb spec/factories/goals.rb spec/models/goal_spec.rb spec/models/transaction_goal_spec.rb
git commit -m "Goal model and transaction goal links

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `GoalMatcher`, rematch on goal changes, reorder, delete cleanup

**Files:**
- Create: `app/services/goal_matcher.rb`
- Modify: `app/models/goal.rb`
- Test: `spec/services/goal_matcher_spec.rb`, `spec/models/goal_spec.rb`

**Interfaces:**
- Consumes: `Goal#matcher?`, `#matcher_rule`, scopes (Task 3); `RuleEngine.matches?(rule, attrs)`; `Transaction#rule_attributes`.
- Produces:
  - `GoalMatcher.new(book).apply(transactions) → Integer` (rows linked)
  - `GoalMatcher.new(book).rematch → Integer`
  - `Goal#rematched_count → Integer | nil` (set after a save that rematched)
  - `Goal#move_to!(position) → Goal`

- [ ] **Step 1: Write the failing service spec**

`spec/services/goal_matcher_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe GoalMatcher do
  let(:book) { create(:business) }
  let(:account) { create(:account, business: book) }

  def txn(payee, cents = -100_00, **attrs) = create(:transaction, account: account, payee: payee, amount_cents: cents, **attrs)

  # Goals rematch when created (Task 4's callback), so each example creates its goals before the rows they should match.
  def goal(**attrs) = create(:goal, business: book, **attrs)

  it "links eligible outflows to the first matching active goal by position" do
    first = goal(match_value: "tony")
    second = goal(match_value: "tony russo")
    rows = [ txn("ZELLE TONY RUSSO"), txn("TONY RUSSO REFUND", 50_00), txn("KROGER"), txn("TONY", excluded: true) ]
    expect(described_class.new(book).apply(rows)).to eq(1)
    expect(rows.map { _1.reload.goal }).to eq([ first, nil, nil, nil ])
    expect(rows.first.goal_linked_by).to eq("matcher")
    expect(second.transactions).to be_empty
  end

  it "skips archived goals, goals without a matcher, and rows already linked or unlinked by hand" do
    goal(match_value: "tony", archived_at: Time.current)
    goal(match_field: nil, match_operator: nil, match_value: nil)
    hand_goal = goal(match_value: "zzz")
    rows = [ txn("TONY", goal: hand_goal, goal_linked_by: "user"), txn("TONY", goal_linked_by: "user"), txn("TONY") ]
    expect(described_class.new(book).apply(rows)).to eq(0)
    expect(rows.map { _1.reload.goal }).to eq([ hand_goal, nil, nil ])
  end

  it "respects the matcher's amount range against the absolute amount" do
    goal(match_value: "tony", match_amount_min: "1,000", match_amount_max: "2,000")
    rows = [ txn("TONY", -999_99), txn("TONY", -1_500_00), txn("TONY", -2_000_01) ]
    described_class.new(book).apply(rows)
    expect(rows.map { _1.reload.goal_id.present? }).to eq([ false, true, false ])
  end

  it "only touches goal columns, even on rows that would fail validation" do
    goal(match_value: "tony")
    row = txn("TONY")
    row.update_column(:sales_tax_period_starts_on, Date.new(1999, 1, 1))
    expect { described_class.new(book).apply([ row ]) }.not_to raise_error
    expect(row.reload.goal_linked_by).to eq("matcher")
  end

  describe "#rematch" do
    it "relinks every eligible row in the book, keeping hand links and archived goals' links" do
      old = goal(match_value: "tony")
      archived = goal(match_value: "tony")
      kept = txn("TONY OLD", goal: archived, goal_linked_by: "matcher")
      archived.update_column(:archived_at, Time.current)
      hand = txn("TONY HAND", goal: old, goal_linked_by: "user")
      auto = txn("TONY AUTO", goal: old, goal_linked_by: "matcher")
      fresh = txn("TONY NEW")
      other_book = create(:transaction, payee: "TONY")
      top = goal(match_value: "tony")
      top.update_column(:position, 0)
      expect(described_class.new(book).rematch).to eq(2)
      expect([ kept, hand, auto, fresh, other_book ].map { _1.reload.goal }).to eq([ archived, old, top, top, nil ])
    end
  end
end
```

Add to `spec/models/goal_spec.rb`:

```ruby
  describe "matching on save" do
    let(:account) { create(:account, business: book) }

    it "backfills existing transactions when created and reports the count" do
      create(:transaction, account: account, payee: "ZELLE TONY", amount_cents: -500_00)
      goal = create(:goal, business: book)
      expect(goal.rematched_count).to eq(1)
      expect(goal.transactions.count).to eq(1)
    end

    it "relinks when the matcher changes but not on a rename" do
      tony = create(:transaction, account: account, payee: "ZELLE TONY", amount_cents: -500_00)
      ann = create(:transaction, account: account, payee: "ZELLE ANN", amount_cents: -500_00)
      goal = create(:goal, business: book)
      goal.update!(name: "Renamed")
      expect(goal.rematched_count).to be_nil
      goal.update!(match_value: "ann")
      expect([ tony, ann ].map { _1.reload.goal_id }).to eq([ nil, goal.id ])
    end

    it "keeps links when archived and relinks once when unarchived" do
      row = create(:transaction, account: account, payee: "TONY", amount_cents: -500_00)
      goal = create(:goal, business: book)
      goal.update!(archived_at: Time.current)
      expect(row.reload.goal).to eq(goal)
      goal.update!(archived_at: nil)
      expect(row.reload.goal).to eq(goal)
      expect(Transaction.where(goal: goal).count).to eq(1)
    end

    it "gives matcher links to the new top goal after a reorder, leaving hand links alone" do
      first = create(:goal, business: book, match_value: "tony")
      second = create(:goal, business: book, match_value: "tony")
      auto = create(:transaction, account: account, payee: "TONY", amount_cents: -500_00)
      GoalMatcher.new(book).rematch
      hand = create(:transaction, account: account, payee: "TONY", amount_cents: -500_00, goal: first, goal_linked_by: "user")
      expect(auto.reload.goal).to eq(first)
      second.move_to!(1)
      expect(book.goals.ordered).to eq([ second, first ])
      expect([ auto, hand ].map { _1.reload.goal }).to eq([ second, first ])
    end

    it "frees matcher links and turns hand links into hand unlinks when deleted" do
      goal = create(:goal, business: book)
      auto = create(:transaction, account: account, payee: "TONY", amount_cents: -500_00)
      GoalMatcher.new(book).rematch
      hand = create(:transaction, account: account, payee: "X", amount_cents: -500_00, goal: goal, goal_linked_by: "user")
      goal.destroy!
      expect(auto.reload.attributes.values_at("goal_id", "goal_linked_by")).to eq([ nil, nil ])
      expect(hand.reload.attributes.values_at("goal_id", "goal_linked_by")).to eq([ nil, "user" ])
    end
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bundle exec rspec spec/services/goal_matcher_spec.rb spec/models/goal_spec.rb`
Expected: FAIL with `NameError: uninitialized constant GoalMatcher`.

- [ ] **Step 3: Service**

`app/services/goal_matcher.rb`:

```ruby
# Links transactions to a book's payment goals. A row is eligible when it's an outflow, not excluded, and has no goal
# link of any kind (a hand unlink leaves goal_linked_by "user", which keeps the matcher away). The first active goal
# by position whose matcher hits wins. Only goal columns are written, so categorization is never touched.
class GoalMatcher
  def initialize(book)
    @book = book
    @goals = book.goals.active.payments.ordered.to_a.select(&:matcher?)
  end

  def apply(transactions)
    return 0 if @goals.empty?

    transactions.count do |txn|
      next false unless eligible?(txn)

      goal = @goals.find { RuleEngine.matches?(_1.matcher_rule, txn.rule_attributes) }
      next false unless goal

      txn.update_columns(goal_id: goal.id, goal_linked_by: "matcher", updated_at: Time.current)
      true
    end
  end

  # Clears every active payment goal's matcher links in the book, then matches again. Archived goals keep their links.
  def rematch
    Transaction.where(goal_id: @book.goals.active.payments.select(:id), goal_linked_by: "matcher")
      .update_all(goal_id: nil, goal_linked_by: nil, updated_at: Time.current)
    apply(Transaction.for_businesses(@book.id).where(goal_id: nil, goal_linked_by: nil, excluded: false)
      .where("transactions.amount_cents < 0").order(:posted_on, :id).to_a)
  end

  private

  def eligible?(txn) = txn.goal_id.nil? && txn.goal_linked_by.nil? && !txn.excluded? && txn.amount_cents.to_i.negative?
end
```

- [ ] **Step 4: Goal callbacks and reorder**

In `app/models/goal.rb`:
- add `attr_reader :rematched_count` under the `money_attribute` lines
- add `after_save :rematch_after_save, if: :rematch_needed?` and `before_destroy :release_transactions` after the `before_create` line
- add the public method:

```ruby
  def move_to!(new_position)
    ApplicationRecord.transaction do
      ids = business.goals.ordered.where.not(id: id).pluck(:id)
      ids.insert(new_position.to_i.clamp(1, ids.size + 1) - 1, id)
      ids.each.with_index(1) { |goal_id, position| Goal.where(id: goal_id).update_all(position: position) }
      GoalMatcher.new(business).rematch if payments?
    end
    reload
  end
```

- add next to `KINDS`: `MATCH_COLUMNS = %w[match_field match_operator match_value match_amount_min_cents match_amount_max_cents archived_at].freeze`
- add under `private`:

```ruby
  def rematch_needed? = payments? && (previously_new_record? || saved_changes.keys.intersect?(MATCH_COLUMNS))

  def rematch_after_save
    @rematched_count = GoalMatcher.new(business).rematch
  end

  def release_transactions
    transactions.where(goal_linked_by: "matcher").update_all(goal_id: nil, goal_linked_by: nil, updated_at: Time.current)
    transactions.update_all(goal_id: nil, updated_at: Time.current)
  end
```
- [ ] **Step 5: Run the specs, rubocop, commit**

Run: `bundle exec rspec spec/services/goal_matcher_spec.rb spec/models/goal_spec.rb spec/models/transaction_goal_spec.rb && bin/rubocop`
Expected: PASS.

```bash
git add app/services/goal_matcher.rb app/models/goal.rb spec/services/goal_matcher_spec.rb spec/models/goal_spec.rb
git commit -m "GoalMatcher links outflows to payment goals; goals rematch on change, reorder and delete

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Match goals on CSV import, Plaid sync, and manual entry

**Files:**
- Modify: `app/models/csv_import.rb`, `app/services/plaid_feed/sync.rb`, `app/controllers/transactions_controller.rb`
- Test: `spec/models/csv_import_spec.rb`, `spec/services/plaid_feed/sync_spec.rb`, `spec/requests/transactions_spec.rb`

**Interfaces:**
- Consumes: `GoalMatcher.new(book).apply(rows)` (Task 4).

- [ ] **Step 1: Write the failing specs**

`spec/models/csv_import_spec.rb`: add after "commits new rows, applies rules, and records counts". It uses that file's `business`, `account` and `upload`. The fixture `spec/fixtures/files/checking.csv` has an "ADOBE CREATIVE CLOUD" outflow.

```ruby
  it "links committed rows to matching payment goals" do
    goal = create(:goal, business: business, match_value: "adobe")
    upload.commit!
    expect(account.transactions.find_by!(payee: "ADOBE CREATIVE CLOUD")).to have_attributes(goal_id: goal.id, goal_linked_by: "matcher")
  end
```

`spec/services/plaid_feed/sync_spec.rb`, add:

```ruby
  it "links inserted rows to matching payment goals" do
    goal = create(:goal, business: book, match_value: "tony")
    page(added: [ plaid("t1", amount: 1500.0, date: "2026-10-01", name: "ZELLE TONY RUSSO") ])
    sync
    expect(checking.transactions.sole.goal).to eq(goal)
  end
```

`spec/requests/transactions_spec.rb`, add:

```ruby
  describe "goals on manual entry" do
    let!(:book) { create(:business) }
    let!(:account) { create(:account, business: book) }

    it "links a new manual outflow by the goal's matcher" do
      goal = create(:goal, business: book)
      sign_in_as user_with_role("editor", book)
      post business_transactions_path(book), params: { transaction: { account_id: account.id, posted_on: "2026-10-01", payee: "Tony Russo",
                                                                       amount: "1,500.00", direction: "out" } }
      expect(account.transactions.sole).to have_attributes(goal_id: goal.id, goal_linked_by: "matcher")
    end
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bundle exec rspec spec/models/csv_import_spec.rb spec/services/plaid_feed/sync_spec.rb spec/requests/transactions_spec.rb`
Expected: the three new examples FAIL (no goal linked).

- [ ] **Step 3: Call sites**

`app/models/csv_import.rb` `commit!`, right after `RuleApplier.new(account.business).apply(created)`:

```ruby
      GoalMatcher.new(account.business).apply(created)
```

`app/services/plaid_feed/sync.rb` `call`, replace the `fresh.group_by…` line with:

```ruby
        fresh.group_by { _1.account.business }.each do |book, rows|
          RuleApplier.new(book).apply(rows)
          GoalMatcher.new(book).apply(rows)
        end
```

`app/controllers/transactions_controller.rb` `create`, change `if @transaction.save` to:

```ruby
    if @transaction.save
      GoalMatcher.new(@business).apply([ @transaction ])
      redirect_after_save("Transaction added.")
```

(Keep the rest of the branch as it is.)

- [ ] **Step 4: Run the specs, rubocop, commit**

Run: `bundle exec rspec spec/models/csv_import_spec.rb spec/models/csv_import_plaid_spec.rb spec/services/plaid_feed spec/requests/transactions_spec.rb && bin/rubocop`
Expected: PASS.

```bash
git add app/models/csv_import.rb app/services/plaid_feed/sync.rb app/controllers/transactions_controller.rb spec/models/csv_import_spec.rb spec/services/plaid_feed/sync_spec.rb spec/requests/transactions_spec.rb
git commit -m "Match payment goals on CSV import, Plaid sync and manual entry

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `Goals::Progress` and `Goals::BalanceHistory`

**Files:**
- Create: `app/models/goals/progress.rb`, `app/models/goals/balance_history.rb`
- Test: `spec/models/goals/progress_spec.rb`, `spec/models/goals/balance_history_spec.rb`

**Interfaces:**
- Consumes: `Account#balance_cents` (Task 1); `Goal` (Task 3).
- Produces:
  - `Goals::Progress.for_book(book) → Array<Goals::Progress::Row>` (active goals, ordered)
  - `Goals::Progress.for_goals(goals) → Array<Row>` (same order as given)
  - `Row` has `goal`, `saved_cents`, `target_cents`, `met?`, `percent` (Integer 0–100), and `balance_unknown?`.
  - `Goals::BalanceHistory.for(account, today: Date.current) → Array<Goals::BalanceHistory::Entry>`, newest first. `Entry` has `txn` and `balance_cents` (after that row).

- [ ] **Step 1: Write the failing specs**

`spec/models/goals/progress_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Goals::Progress do
  let(:book) { create(:business) }
  let(:savings) { create(:account, business: book, kind: "savings", opening_balance: "8,000", opening_balance_on: Date.new(2026, 1, 1)) }

  def savings_goal(name, target) = create(:goal, :savings, business: book, account: savings, name: name, target: target)
  def summary(rows) = rows.map { [ _1.goal.name, _1.saved_cents, _1.met?, _1.percent ] }

  it "fills savings goals on one account in priority order" do
    savings_goal("Nest egg", "6,000")
    savings_goal("Truck", "10,000")
    expect(summary(described_class.for_book(book))).to eq([ [ "Nest egg", 6_000_00, true, 100 ], [ "Truck", 2_000_00, false, 20 ] ])
  end

  it "takes withdrawals from the lowest priority first, and a reorder flips the allocation" do
    savings_goal("Nest egg", "6,000")
    truck = savings_goal("Truck", "10,000")
    create(:transaction, account: savings, posted_on: Date.new(2026, 2, 1), amount_cents: -500_00)
    expect(summary(described_class.for_book(book)).map(&:second)).to eq([ 6_000_00, 1_500_00 ])
    truck.move_to!(1)
    expect(summary(described_class.for_book(book))).to eq([ [ "Truck", 7_500_00, false, 75 ], [ "Nest egg", 0, false, 0 ] ])
  end

  it "fills nothing from a negative balance and flags an unknown one" do
    savings_goal("Nest egg", "6,000")
    create(:transaction, account: savings, posted_on: Date.new(2026, 2, 1), amount_cents: -9_000_00)
    expect(described_class.for_book(book).sole.saved_cents).to eq(0)

    plaid = create(:account, :plaid, business: book, kind: "savings")
    create(:goal, :savings, business: book, account: plaid)
    row = described_class.for_book(book).last
    expect(row).to be_balance_unknown
    expect(row).not_to be_met
  end

  it "sums payment goals' linked non-excluded outflows, net of refunds, never below zero" do
    goal = create(:goal, business: book, target: "1,000", match_field: nil, match_operator: nil, match_value: nil)
    account = create(:account, business: book)
    create(:transaction, account: account, amount_cents: -600_00, goal: goal, goal_linked_by: "user")
    create(:transaction, account: account, amount_cents: 100_00, goal: goal, goal_linked_by: "user")
    create(:transaction, account: account, amount_cents: -900_00, goal: goal, goal_linked_by: "user", excluded: true)
    row = described_class.for_book(book).sole
    expect([ row.saved_cents, row.percent, row.met? ]).to eq([ 500_00, 50, false ])

    refund_only = create(:goal, business: book, match_field: nil, match_operator: nil, match_value: nil)
    create(:transaction, account: account, amount_cents: 50_00, goal: refund_only, goal_linked_by: "user")
    expect(described_class.for_goals([ refund_only ]).sole.saved_cents).to eq(0)
  end

  it "caps percent at 100 and leaves archived goals out of the book" do
    goal = create(:goal, business: book, target: "100", match_field: nil, match_operator: nil, match_value: nil)
    create(:transaction, account: create(:account, business: book), amount_cents: -250_00, goal: goal, goal_linked_by: "user")
    expect(described_class.for_book(book).sole.percent).to eq(100)
    goal.update!(archived_at: Time.current)
    expect(described_class.for_book(book)).to be_empty
  end
end
```

`spec/models/goals/balance_history_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Goals::BalanceHistory do
  let(:today) { Date.new(2026, 10, 14) }

  it "runs forward from the opening balance for manual accounts, newest first" do
    account = create(:account, opening_balance: "1,000", opening_balance_on: Date.new(2026, 1, 1))
    create(:transaction, account: account, posted_on: Date.new(2026, 1, 1), amount_cents: -1_00)
    a = create(:transaction, account: account, posted_on: Date.new(2026, 2, 1), amount_cents: -200_00)
    b = create(:transaction, account: account, posted_on: Date.new(2026, 3, 1), amount_cents: 50_00)
    create(:transaction, account: account, posted_on: Date.new(2026, 3, 2), amount_cents: -5_00, excluded: true)
    expect(described_class.for(account, today:).map { [ _1.txn, _1.balance_cents ] }).to eq([ [ b, 850_00 ], [ a, 800_00 ] ])
  end

  it "runs backward from the reported balance for Plaid accounts over the last 12 months" do
    account = create(:account, :plaid, reported_balance_cents: 1_000_00, balance_reported_at: Time.current)
    create(:transaction, account: account, posted_on: Date.new(2025, 10, 13), amount_cents: -1_00)
    a = create(:transaction, account: account, posted_on: Date.new(2026, 9, 1), amount_cents: -200_00)
    b = create(:transaction, account: account, posted_on: Date.new(2026, 10, 1), amount_cents: 50_00)
    expect(described_class.for(account, today:).map { [ _1.txn, _1.balance_cents ] }).to eq([ [ b, 1_000_00 ], [ a, 950_00 ] ])
  end

  it "is empty when the balance is unknown" do
    expect(described_class.for(create(:account), today:)).to eq([])
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bundle exec rspec spec/models/goals`
Expected: FAIL with `NameError: uninitialized constant Goals`.

- [ ] **Step 3: Implement**

`app/models/goals/progress.rb`:

```ruby
module Goals
  # How far each goal has come. Payment goals: the linked, non-excluded outflows net of refunds. Savings goals: their
  # account's balance poured into the active savings goals on that account, highest priority first.
  class Progress
    Row = Data.define(:goal, :saved_cents, :balance_unknown) do
      def target_cents = goal.target_cents
      def balance_unknown? = balance_unknown
      def met? = !balance_unknown && saved_cents >= target_cents
      def percent = [ saved_cents * 100 / target_cents, 100 ].min
    end

    def self.for_book(book) = for_goals(book.goals.active.ordered.includes(:account))

    def self.for_goals(goals)
      goals = goals.to_a
      paid = Transaction.where(goal_id: goals.select(&:payments?).map(&:id), excluded: false).group(:goal_id).sum(:amount_cents)
      allocated = allocate(goals.select { _1.savings? && !_1.archived? })
      goals.map do |goal|
        if goal.payments?
          Row.new(goal:, saved_cents: [ -paid.fetch(goal.id, 0), 0 ].max, balance_unknown: false)
        else
          allocated.fetch(goal.id) { Row.new(goal:, saved_cents: 0, balance_unknown: false) }
        end
      end
    end

    def self.allocate(savings_goals)
      savings_goals.sort_by { [ _1.position, _1.id ] }.group_by(&:account).each_with_object({}) do |(account, goals), rows|
        balance = account.balance_cents
        remaining = [ balance.to_i, 0 ].max
        goals.each do |goal|
          share = balance.nil? ? 0 : [ goal.target_cents, remaining ].min
          remaining -= share
          rows[goal.id] = Row.new(goal:, saved_cents: share, balance_unknown: balance.nil?)
        end
      end
    end
    private_class_method :allocate
  end
end
```

`app/models/goals/balance_history.rb`:

```ruby
module Goals
  # An account's non-excluded transactions, newest first, each with the balance after it. Manual and CSV accounts run
  # forward from the opening balance; Plaid accounts run backward from the reported balance over the last 12 months.
  class BalanceHistory
    Entry = Data.define(:txn, :balance_cents)

    def self.for(account, today: Date.current)
      return [] unless account.balance_known?

      rows = account.transactions.where(excluded: false)
      if account.plaid?
        balance = account.reported_balance_cents
        rows.where(posted_on: (today << 12)..).order(posted_on: :desc, id: :desc).map do |txn|
          Entry.new(txn:, balance_cents: balance).tap { balance -= txn.amount_cents }
        end
      else
        balance = account.opening_balance_cents
        rows.where("posted_on > ?", account.opening_balance_on).order(:posted_on, :id)
          .map { |txn| Entry.new(txn:, balance_cents: balance += txn.amount_cents) }.reverse
      end
    end
  end
end
```

- [ ] **Step 4: Run the specs, rubocop, commit**

Run: `bundle exec rspec spec/models/goals && bin/rubocop`
Expected: PASS.

```bash
git add app/models/goals spec/models/goals
git commit -m "Goal progress (payments sum, savings waterfall) and account balance history

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Goals page: list, create, edit, reorder, archive, delete; sidebar link

**Files:**
- Create: `app/controllers/goals_controller.rb`, `app/views/goals/index.html.erb`, `app/views/goals/new.html.erb`, `app/views/goals/edit.html.erb`, `app/views/goals/_form.html.erb`, `app/views/goals/_bar.html.erb`, `app/javascript/controllers/goal_kind_controller.js`, `app/assets/stylesheets/components/goals.css`
- Modify: `config/routes.rb`, `app/views/layouts/_sidebar.html.erb`
- Test: `spec/requests/goals_spec.rb`

**Interfaces:**
- Consumes: `Goal`, `Goal#move_to!`, `Goal#rematched_count`, `Goals::Progress.for_book`, `Goals::Progress.for_goals`.
- Produces:
  - Routes `business_goals_path`, `new_business_goal_path`, `business_goal_path` (show is added in Task 8), `edit_business_goal_path`, `move_business_goal_path`, `archive_business_goal_path`, `unarchive_business_goal_path`.
  - Partial `goals/_bar` (locals `row:`).

- [ ] **Step 1: Write the failing request spec**

`spec/requests/goals_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Goals" do
  let!(:book) { create(:business) }
  let!(:savings) { create(:account, business: book, name: "Savings", kind: "savings", opening_balance: "8,000", opening_balance_on: Date.new(2026, 1, 1)) }
  let(:payment_params) { { name: "Pay back Uncle Tony", kind: "payments", target: "30,000", target_date: "",
                           match_field: "payee", match_operator: "contains", match_value: "tony", match_amount_min: "", match_amount_max: "" } }

  it "lets an editor create a payment goal and reports how many transactions it linked" do
    create(:transaction, account: savings, payee: "ZELLE TONY", amount_cents: -1_500_00)
    sign_in_as user_with_role("editor", book)
    post business_goals_path(book), params: { goal: payment_params }
    expect(response).to redirect_to(business_goals_path(book))
    expect(flash[:notice]).to eq("Goal saved. 1 existing transaction linked.")
    expect(book.goals.sole).to have_attributes(name: "Pay back Uncle Tony", target_cents: 30_000_00, kind: "payments")
  end

  it "creates a savings goal on an account in the book" do
    sign_in_as user_with_role("editor", book)
    post business_goals_path(book), params: { goal: { name: "Nest egg", kind: "savings", target: "6,000", account_id: savings.id } }
    expect(book.goals.sole).to have_attributes(account: savings, kind: "savings")
    expect(flash[:notice]).to eq("Goal saved.")
  end

  it "re-renders with errors for another book's account or a credit account" do
    sign_in_as user_with_role("editor", book)
    post business_goals_path(book), params: { goal: { name: "x", kind: "savings", target: "1", account_id: create(:account).id } }
    expect(response).to have_http_status(:unprocessable_content)
    post business_goals_path(book), params: { goal: { name: "x", kind: "savings", target: "1",
                                                      account_id: create(:account, business: book, kind: "credit").id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Goal.count).to eq(0)
  end

  it "ignores a kind change on update" do
    goal = create(:goal, business: book)
    sign_in_as user_with_role("editor", book)
    patch business_goal_path(book, goal), params: { goal: payment_params.merge(kind: "savings", name: "Tony") }
    expect(goal.reload).to have_attributes(kind: "payments", name: "Tony")
  end

  it "lists active goals with progress, and archived goals under Completed" do
    create(:goal, :savings, business: book, account: savings, name: "Nest egg", target: "6,000")
    create(:goal, business: book, name: "Old loan", archived_at: Time.current)
    sign_in_as user_with_role("viewer", book)
    get business_goals_path(book)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".goal-list").text).to include("Nest egg").and include("$6,000.00 of $6,000.00").and include("Met")
    expect(page.at_css(".goal-completed").text).to include("Old loan")
    expect(page.css(".drag-handle")).to be_empty
    expect(response.body).not_to include("New goal")
  end

  it "reorders, archives, unarchives and deletes" do
    a = create(:goal, business: book)
    b = create(:goal, business: book)
    sign_in_as user_with_role("editor", book)
    patch move_business_goal_path(book, b), params: { position: 1 }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(book.goals.ordered).to eq([ b, a ])
    patch archive_business_goal_path(book, a)
    expect(a.reload).to be_archived
    patch unarchive_business_goal_path(book, a)
    expect(a.reload).not_to be_archived
    delete business_goal_path(book, a)
    expect(response).to redirect_to(business_goals_path(book))
    expect(Goal.exists?(a.id)).to be(false)
  end

  it "forbids viewers from writing and hides other books' goals" do
    goal = create(:goal, business: book)
    sign_in_as user_with_role("viewer", book)
    post business_goals_path(book), params: { goal: payment_params }
    expect(response).to have_http_status(:forbidden)
    patch move_business_goal_path(book, goal), params: { position: 1 }, as: :json
    expect(response).to have_http_status(:forbidden)
    patch archive_business_goal_path(book, goal)
    expect(response).to have_http_status(:forbidden)
    delete business_goal_path(book, goal)
    expect(response).to have_http_status(:forbidden)

    other = create(:goal)
    sign_in_as user_with_role("editor", book)
    patch business_goal_path(book, other), params: { goal: { name: "x" } }
    expect(response).to have_http_status(:not_found)
    get business_goals_path(other.business)
    expect(response).to have_http_status(:not_found)
  end

  it "shows Goals in the book's sidebar" do
    sign_in_as user_with_role("viewer", book)
    get business_path(book)
    expect(response.body).to include(%(href="#{business_goals_path(book)}"))
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/goals_spec.rb`
Expected: FAIL with `NoMethodError: undefined method 'business_goals_path'`.

- [ ] **Step 3: Routes and sidebar**

`config/routes.rb`, inside `resources :businesses … do`, after the `resources :rules … end` block:

```ruby
    resources :goals, except: :show, concerns: :archivable do
      patch :move, on: :member
    end
```

(Task 8 changes `except: :show` to a full `resources :goals` and nests the links.)

`app/views/layouts/_sidebar.html.erb`, after the Rules `nav_link`:

```erb
    <%= nav_link "Goals", business_goals_path(business) %>
```

- [ ] **Step 4: Controller**

`app/controllers/goals_controller.rb`:

```ruby
class GoalsController < ApplicationController
  include BusinessScoped
  include Archiving

  FIELDS = %i[name target target_date account_id match_field match_operator match_value match_amount_min match_amount_max].freeze

  before_action :require_editor!, except: :index
  before_action :set_goal, only: %i[edit update destroy move archive unarchive]

  def index
    @rows = Goals::Progress.for_book(@business)
    @completed = @business.goals.where.not(archived_at: nil).order(archived_at: :desc)
  end

  def new
    @goal = @business.goals.new(kind: params[:kind] == "savings" ? "savings" : "payments", match_field: "payee", match_operator: "contains")
  end

  def create
    @goal = @business.goals.new(params.expect(goal: [ :kind, *FIELDS ]))
    if @goal.save
      redirect_to business_goals_path(@business), notice: saved_notice
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @goal.update(params.expect(goal: FIELDS))
      redirect_to business_goals_path(@business), notice: saved_notice
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @goal.destroy!
    redirect_to business_goals_path(@business), notice: "Goal deleted.", status: :see_other
  end

  def move
    @goal.move_to!(params.expect(:position))
    head :no_content
  end

  private

  def archivable = @goal

  def set_goal
    @goal = @business.goals.find(params[:id])
  end

  def saved_notice
    count = @goal.rematched_count
    count ? "Goal saved. #{count} existing #{"transaction".pluralize(count)} linked." : "Goal saved."
  end
end
```

`account_id` is checked by `Goal#savings_account_usable` (same book, active, not credit), so a crafted id is a validation error. Updates never permit `kind`.

On an archive or unarchive of a payment goal, the rematch count isn't shown; the `Archiving` concern's notice ("Goal archived.") is used.

- [ ] **Step 5: Views, Stimulus, CSS**

`app/views/goals/_bar.html.erb`:

```erb
<%# One goal's progress: bar, "$x of $y", and a Met badge. %>
<% goal = row.goal %>
<div class="goal-bar">
  <% if row.balance_unknown? %>
    <span class="muted"><%= goal.account.plaid? ? "Waiting for the bank's balance" : "Set an opening balance on #{goal.account.name}" %></span>
  <% else %>
    <span class="goal-track"><span class="goal-fill<%= " met" if row.met? %>" style="width: <%= row.percent %>%"></span></span>
    <span class="goal-amounts num"><%= money(row.saved_cents) %> of <%= money(row.target_cents) %></span>
    <% if row.met? %><span class="badge badge-pos">Met</span><% end %>
  <% end %>
</div>
```

`app/views/goals/index.html.erb`:

```erb
<% content_for :title, "Goals" %>
<header class="page-header">
  <h1>Goals</h1>
  <%= primary_action "New goal", new_business_goal_path(@business) if current_membership.can_edit? %>
</header>
<p>Payment goals add up the payments linked to them. Savings goals share their account's balance, top of the list first.<%= " Drag ≡ to reorder." if current_membership.can_edit? %></p>
<% if @rows.empty? %>
  <div class="empty"><strong>No goals yet</strong>Track paying something off, or saving toward a target.</div>
<% else %>
  <table class="goal-list">
    <thead><tr><th></th><th>Goal</th><th>Progress</th><th></th></tr></thead>
    <tbody <%= tag.attributes(data: { controller: "sortable" }) if current_membership.can_edit? %>>
      <% @rows.each do |row| %>
        <% goal = row.goal %>
        <tr id="<%= dom_id(goal) %>" data-sortable-url="<%= move_business_goal_path(@business, goal) %>">
          <td><% if current_membership.can_edit? %><span class="drag-handle" title="Drag to reorder">≡</span><% end %></td>
          <td>
            <strong><%= goal.name %></strong>
            <small class="muted">
              <% if goal.savings? %>Savings · <%= goal.account.name %><% else %>Payments · <%= goal.matcher? ? goal.matcher_description : "Linked by hand" %><% end %>
              <% if goal.target_date %> · by <%= l(goal.target_date, format: :long) %><% end %>
            </small>
          </td>
          <td><%= render "goals/bar", row: row %></td>
          <td>
            <% if current_membership.can_edit? %>
              <div class="button-group">
                <%= link_to "Edit", edit_business_goal_path(@business, goal) %>
                <%= archive_button [ @business, goal ] %>
              </div>
            <% end %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>
<% if @completed.any? %>
  <details class="goal-completed">
    <summary>Completed (<%= @completed.size %>)</summary>
    <ul class="plain-list">
      <% @completed.each do |goal| %>
        <li id="<%= dom_id(goal) %>">
          <%= goal.name %> <span class="muted">· target <%= money(goal.target_cents) %></span>
          <%= archive_button [ @business, goal ] if current_membership.can_edit? %>
        </li>
      <% end %>
    </ul>
  </details>
<% end %>
```

`app/views/goals/_form.html.erb`:

```erb
<%= form_with model: [ @business, goal ], data: { controller: "goal-kind" } do |f| %>
  <%= render "shared/errors", record: goal %>
  <p><%= f.label :name %> <%= f.text_field :name, required: true, maxlength: 100 %></p>
  <% if goal.new_record? %>
    <p>
      <label><%= f.radio_button :kind, "payments", data: { action: "goal-kind#toggle" } %> Payments: count payments toward a total</label>
      <label><%= f.radio_button :kind, "savings", data: { action: "goal-kind#toggle" } %> Savings: fill from an account's balance</label>
    </p>
  <% end %>
  <p>
    <%= f.label :target %> <%= f.text_field :target, size: 12, inputmode: "decimal", required: true %>
    <%= f.label :target_date, "by (optional)" %> <%= f.date_field :target_date %>
  </p>
  <fieldset data-goal-kind-target="payments" <%= "hidden" if goal.savings? %>>
    <legend>Link payments automatically (optional)</legend>
    <p>
      When
      <%= f.select :match_field, Rule::FIELDS.map { [ _1.humanize, _1 ] } %>
      <%= f.select :match_operator, Rule::OPERATORS.map { [ _1.humanize(capitalize: false), _1 ] } %>
      <%= f.text_field :match_value, maxlength: 100, placeholder: "e.g. tony" %>
    </p>
    <p>
      and amount between <%= f.text_field :match_amount_min, size: 8, placeholder: "any" %>
      and <%= f.text_field :match_amount_max, size: 8, placeholder: "any" %>
    </p>
    <p><small>Only money going out is linked. Leave the text blank to link payments by hand from each transaction.</small></p>
  </fieldset>
  <fieldset data-goal-kind-target="savings" <%= "hidden" unless goal.savings? %>>
    <legend>Account</legend>
    <p>
      <%= f.collection_select :account_id, @business.accounts.active.where.not(kind: "credit").order(:name), :id, :name,
            include_blank: "Choose an account" %>
    </p>
  </fieldset>
  <%= f.submit "Save goal" %>
<% end %>
```

A hidden fieldset still submits its fields. The model's `clear_other_kind_fields` discards the other kind's values, so no JS is needed for correctness.

`app/views/goals/new.html.erb`:

```erb
<% content_for :title, "New goal" %>
<header class="page-header"><h1>New goal</h1></header>
<%= render "form", goal: @goal %>
```

`app/views/goals/edit.html.erb`:

```erb
<% content_for :title, "Edit goal" %>
<header class="page-header"><h1>Edit goal</h1></header>
<%= render "form", goal: @goal %>
<%= confirm_button "Delete goal", business_goal_path(@business, @goal), method: :delete,
      confirm: "Delete this goal? Its transactions stay; they're just no longer linked. Archive it instead to keep its history." %>
```

`app/javascript/controllers/goal_kind_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Shows the matcher fields for payment goals and the account select for savings goals.
export default class extends Controller {
  static targets = ["payments", "savings"]

  toggle(event) {
    const savings = event.target.value === "savings"
    this.paymentsTarget.hidden = savings
    this.savingsTarget.hidden = !savings
  }
}
```

(`app/javascript/controllers/index.js` uses `eagerLoadControllersFrom`, so the new file is registered automatically.)

`app/assets/stylesheets/components/goals.css`:

```css
.goal-bar { display: flex; align-items: center; gap: var(--space-2); font-size: var(--text-sm); }
.goal-track { flex: 1; min-width: 6rem; height: 8px; background: var(--chart-grid); border-radius: 999px; overflow: hidden; }
.goal-fill { display: block; height: 100%; background: var(--accent); border-radius: 999px; }
.goal-fill.met { background: var(--pos); }
.goal-amounts { white-space: nowrap; }
.goal-completed { margin-top: var(--space-4); }
.goal-widget ul { list-style: none; margin: 0; padding: 0; }
.goal-widget li { display: grid; grid-template-columns: minmax(0, 9rem) 1fr; gap: var(--space-2); align-items: center; margin: 8px 0; }
.goal-widget li a { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
```
- [ ] **Step 6: Run the specs, rubocop, brakeman, commit**

Run: `bundle exec rspec spec/requests/goals_spec.rb spec/requests/navigation_spec.rb && bin/rubocop && bin/brakeman --no-pager -q`
Expected: PASS, no offenses, no warnings.

```bash
git add config/routes.rb app/controllers/goals_controller.rb app/views/goals app/javascript/controllers/goal_kind_controller.js app/assets/stylesheets/components/goals.css app/views/layouts/_sidebar.html.erb spec/requests/goals_spec.rb
git commit -m "Goals page: create, edit, reorder, archive and delete goals

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Goal report, unlink, and the transaction form's Goal select

**Files:**
- Create: `app/views/goals/show.html.erb`, `app/controllers/goal_links_controller.rb`
- Modify: `config/routes.rb`, `app/controllers/goals_controller.rb`, `app/controllers/transactions_controller.rb`, `app/views/transactions/_form.html.erb`, `app/views/transactions/index.html.erb`
- Test: `spec/requests/goal_reports_spec.rb`, `spec/requests/transactions_spec.rb`

**Interfaces:**
- Consumes: `Goals::Progress.for_book`, `.for_goals`, `Goals::BalanceHistory.for` (Task 6).
- Produces: `business_goal_path(book, goal)` (report) and `business_goal_link_path(book, goal, txn)` (DELETE).

- [ ] **Step 1: Write the failing specs**

`spec/requests/goal_reports_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Goal reports" do
  let!(:book) { create(:business) }
  let!(:checking) { create(:account, business: book, name: "Checking") }

  it "lists a payment goal's linked transactions oldest first with a running total" do
    goal = create(:goal, business: book, target: "30,000")
    create(:transaction, account: checking, posted_on: Date.new(2026, 3, 1), payee: "ZELLE TONY", amount_cents: -2_000_00, goal: goal, goal_linked_by: "user")
    create(:transaction, account: checking, posted_on: Date.new(2026, 2, 1), payee: "ZELLE TONY", amount_cents: -1_500_00, goal: goal, goal_linked_by: "user")
    create(:transaction, account: checking, posted_on: Date.new(2026, 4, 1), payee: "ZELLE TONY", amount_cents: -9_00, goal: goal, goal_linked_by: "user", excluded: true)
    sign_in_as user_with_role("viewer", book)
    get business_goal_path(book, goal)
    rows = Nokogiri::HTML(response.body).css(".goal-transactions tbody tr").map { _1.css("td").map { |td| td.text.squish } }
    expect(rows.map(&:first)).to eq([ "2026-02-01", "2026-03-01" ])
    expect(rows.map { _1[4] }).to eq([ "$1,500.00", "$3,500.00" ])
    expect(response.body).to include("$3,500.00 of $30,000.00")
    expect(response.body).not_to include("Unlink")
  end

  it "shows a savings goal's allocation and the account's running balance" do
    savings = create(:account, business: book, kind: "savings", opening_balance: "8,000", opening_balance_on: Date.new(2026, 1, 1))
    nest = create(:goal, :savings, business: book, account: savings, name: "Nest egg", target: "6,000")
    create(:goal, :savings, business: book, account: savings, name: "Truck", target: "10,000")
    create(:transaction, account: savings, posted_on: Date.new(2026, 2, 1), payee: "DEPOSIT", amount_cents: 1_000_00)
    sign_in_as user_with_role("viewer", book)
    get business_goal_path(book, nest)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".goal-allocation").text.squish).to include("Nest egg").and include("Truck").and include("$3,000.00 of $10,000.00")
    expect(page.at_css(".goal-history tbody tr").text.squish).to include("DEPOSIT").and include("$9,000.00")
  end

  it "lets an editor unlink a transaction, which stays unlinked when the goal rematches" do
    goal = create(:goal, business: book)
    txn = create(:transaction, account: checking, payee: "ZELLE TONY", amount_cents: -100_00)
    GoalMatcher.new(book).rematch
    sign_in_as user_with_role("editor", book)
    delete business_goal_link_path(book, goal, txn)
    expect(response).to redirect_to(business_goal_path(book, goal))
    expect(txn.reload.attributes.values_at("goal_id", "goal_linked_by")).to eq([ nil, "user" ])
    goal.update!(match_value: "zelle")
    expect(txn.reload.goal_id).to be_nil
  end

  it "rejects unlinking from viewers and for transactions not on the goal" do
    goal = create(:goal, business: book)
    txn = create(:transaction, account: checking, payee: "ZELLE TONY", amount_cents: -100_00)
    GoalMatcher.new(book).rematch
    sign_in_as user_with_role("viewer", book)
    delete business_goal_link_path(book, goal, txn)
    expect(response).to have_http_status(:forbidden)
    sign_in_as user_with_role("editor", book)
    delete business_goal_link_path(book, goal, create(:transaction, payee: "TONY"))
    expect(response).to have_http_status(:not_found)
    expect(txn.reload.goal).to eq(goal)
  end
end
```

Append to `spec/requests/transactions_spec.rb`, inside the `describe "goals on manual entry"` block from Task 5:

```ruby
    it "links and unlinks by hand from the edit form" do
      goal = create(:goal, business: book, match_value: "nobody")
      txn = create(:transaction, account: account, payee: "Tony", amount_cents: -100_00, external_id: "x1")
      sign_in_as user_with_role("editor", book)
      get edit_business_transaction_path(book, txn)
      expect(response.body).to include("transaction[goal_id]")
      patch business_transaction_path(book, txn), params: { transaction: { goal_id: goal.id, memo: "" } }
      expect(txn.reload).to have_attributes(goal_id: goal.id, goal_linked_by: "user")
      patch business_transaction_path(book, txn), params: { transaction: { goal_id: "", memo: "" } }
      expect(txn.reload).to have_attributes(goal_id: nil, goal_linked_by: "user")
    end

    it "rejects another book's goal" do
      txn = create(:transaction, account: account, amount_cents: -100_00)
      sign_in_as user_with_role("editor", book)
      patch business_transaction_path(book, txn), params: { transaction: { goal_id: create(:goal).id } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(txn.reload.goal_id).to be_nil
    end

    it "tags linked rows in the list" do
      goal = create(:goal, business: book, name: "Pay back Tony")
      create(:transaction, account: account, payee: "Tony", amount_cents: -100_00, goal: goal, goal_linked_by: "user")
      sign_in_as user_with_role("viewer", book)
      get business_transactions_path(book)
      expect(Nokogiri::HTML(response.body).at_css(".goal-tag").text).to eq("Pay back Tony")
    end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bundle exec rspec spec/requests/goal_reports_spec.rb spec/requests/transactions_spec.rb`
Expected: FAIL (`business_goal_path` has no `show`; `business_goal_link_path` is undefined; there's no goal select).

- [ ] **Step 3: Routes, controllers**

`config/routes.rb`: replace the Task 7 goals block with:

```ruby
    resources :goals, concerns: :archivable do
      patch :move, on: :member
      resources :links, only: :destroy, controller: "goal_links"
    end
```

`app/controllers/goals_controller.rb`:
- change the editor filter to `before_action :require_editor!, except: %i[index show]`
- add `show` to `set_goal`'s `only:` list
- add the action:

```ruby
  def show
    @row = Goals::Progress.for_book(@business).find { _1.goal == @goal } || Goals::Progress.for_goals([ @goal ]).sole
    if @goal.payments?
      @linked = @goal.transactions.where(excluded: false).includes(:account).order(:posted_on, :id)
    else
      @allocation = Goals::Progress.for_book(@business).select { _1.goal.account_id == @goal.account_id }
      @history = Goals::BalanceHistory.for(@goal.account)
    end
  end
```

`app/controllers/goal_links_controller.rb`:

```ruby
# Unlinks one transaction from a payment goal. The row keeps goal_linked_by "user" so the matcher leaves it alone.
class GoalLinksController < ApplicationController
  include BusinessScoped

  before_action :require_editor!

  def destroy
    goal = @business.goals.find(params[:goal_id])
    txn = goal.transactions.find(params[:id])
    txn.update_columns(goal_id: nil, goal_linked_by: "user", updated_at: Time.current)
    redirect_to business_goal_path(@business, goal), notice: "Transaction unlinked.", status: :see_other
  end
end
```

`app/controllers/transactions_controller.rb`:
- add `goal_id` to both lists: `IMPORTED_EDITABLE = %i[memo category_id transfer excluded goal_id].freeze` and `MANUAL_EDITABLE = %i[posted_on payee amount direction memo category_id transfer excluded goal_id].freeze`
- in `update`, after the `categorized_by` line:

```ruby
    @transaction.goal_linked_by = "user" if @transaction.goal_id_changed?
```

- in `create`, before `apply_inclusive_tax`:

```ruby
    @transaction.goal_linked_by = "user" if @transaction.goal_id.present?
```

`GoalMatcher#apply` skips rows that already have a link, so the Task 5 call after save is a no-op for hand-linked rows.

- [ ] **Step 4: Views**

`app/views/transactions/_form.html.erb`: insert before `<p><%= f.label :transfer %>…`:

```erb
  <% goals = @business.goals.payments.active.or(@business.goals.where(id: transaction.goal_id)).ordered %>
  <% if goals.any? %>
    <p><%= f.label :goal_id, "Goal" %> <%= f.collection_select :goal_id, goals, :id, :name, include_blank: "None" %></p>
  <% end %>
```

`TransactionsController#index`: change `.includes(:account, :category)` to `.includes(:account, :category, :goal)`.

`app/views/transactions/index.html.erb`, in the payee cell: `<td><%= txn.payee %><% if txn.goal %> <span class="badge goal-tag"><%= txn.goal.name %></span><% end %></td>`

`app/views/goals/show.html.erb`:

```erb
<% content_for :title, @goal.name %>
<header class="page-header">
  <div>
    <h1><%= @goal.name %><%= " (archived)" if @goal.archived? %></h1>
    <p class="subtitle">
      Target <%= money(@goal.target_cents) %><% if @goal.target_date %> by <%= l(@goal.target_date, format: :long) %><% end %>
      · <% if @goal.savings? %>Savings in <%= @goal.account.name %><% else %><%= @goal.matcher? ? "Linked when #{@goal.matcher_description}" : "Linked by hand" %><% end %>
    </p>
  </div>
  <% if current_membership.can_edit? %>
    <div class="button-group">
      <%= link_to "Edit", edit_business_goal_path(@business, @goal), class: "button" %>
      <%= archive_button [ @business, @goal ] %>
    </div>
  <% end %>
</header>

<section class="card"><%= render "goals/bar", row: @row %></section>

<% if @goal.payments? %>
  <section class="card">
    <h2 class="card-title">Payments</h2>
    <% if @linked.any? %>
      <table class="goal-transactions">
        <thead><tr><th>Date</th><th>Payee</th><th>Account</th><th class="num">Amount</th><th class="num">Total</th><th></th></tr></thead>
        <tbody>
          <% total = 0 %>
          <% @linked.each do |txn| %>
            <% total -= txn.amount_cents %>
            <tr id="<%= dom_id(txn) %>">
              <td><%= txn.posted_on %></td>
              <td><%= txn.payee %></td>
              <td><%= txn.account.name %></td>
              <td class="num"><%= money(-txn.amount_cents) %></td>
              <td class="num"><%= money(total) %></td>
              <td><%= confirm_button "Unlink", business_goal_link_path(@business, @goal, txn), method: :delete, confirm: "Unlink this payment from the goal?" if current_membership.can_edit? %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% else %>
      <div class="empty"><strong>No payments yet</strong>Matching payments link here automatically, or link one from its transaction.</div>
    <% end %>
  </section>
<% else %>
  <section class="card">
    <h2 class="card-title"><%= @goal.account.name %> · <%= money(@goal.account.balance_cents) %></h2>
    <table class="goal-allocation">
      <tbody>
        <% @allocation.each do |row| %>
          <tr class="<%= "current" if row.goal == @goal %>">
            <td><%= link_to row.goal.name, business_goal_path(@business, row.goal) %></td>
            <td><%= render "goals/bar", row: row %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </section>
  <section class="card">
    <h2 class="card-title">Deposits and withdrawals</h2>
    <% if @history.any? %>
      <table class="goal-history">
        <thead><tr><th>Date</th><th>Payee</th><th class="num">Amount</th><th class="num">Balance</th></tr></thead>
        <tbody>
          <% @history.each do |entry| %>
            <tr>
              <td><%= entry.txn.posted_on %></td>
              <td><%= entry.txn.payee %></td>
              <td class="num"><%= money(entry.txn.amount_cents) %></td>
              <td class="num"><%= money(entry.balance_cents) %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% else %>
      <div class="empty"><strong>No history</strong>
        <%= @goal.account.balance_known? ? "No transactions since the balance date." : "This account's balance isn't known yet." %></div>
    <% end %>
  </section>
<% end %>
```

Append to `app/assets/stylesheets/components/goals.css`:

```css
.goal-allocation tr.current td:first-child { font-weight: 600; }
.goal-tag { margin-left: var(--space-1, 4px); }
```

Make each goal name on the Goals index (Task 7) a link to its report: in `app/views/goals/index.html.erb`, change `<strong><%= goal.name %></strong>` to `<strong><%= link_to goal.name, business_goal_path(@business, goal) %></strong>`.

- [ ] **Step 5: Run the specs, rubocop, brakeman, commit**

Run: `bundle exec rspec spec/requests/goal_reports_spec.rb spec/requests/goals_spec.rb spec/requests/transactions_spec.rb spec/requests/transaction_edit_shortcuts_spec.rb && bin/rubocop && bin/brakeman --no-pager -q`
Expected: PASS, no offenses, no warnings.

```bash
git add config/routes.rb app/controllers/goals_controller.rb app/controllers/goal_links_controller.rb app/controllers/transactions_controller.rb app/views/goals app/views/transactions app/assets/stylesheets/components/goals.css spec/requests/goal_reports_spec.rb spec/requests/transactions_spec.rb
git commit -m "Goal reports, unlinking, and linking by hand from a transaction

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Goals widget on the book overview and the household dashboard

**Files:**
- Create: `app/views/goals/_widget.html.erb`
- Modify: `app/controllers/businesses_controller.rb`, `app/views/businesses/show.html.erb`, `app/models/household_dashboard.rb`, `app/views/dashboards/show.html.erb`
- Test: `spec/requests/goal_widgets_spec.rb`, `spec/models/household_dashboard_spec.rb`

**Interfaces:**
- Consumes: `Goals::Progress.for_book` (Task 6), `goals/_bar` (Task 7).
- Produces: `HouseholdDashboard#goals → Array<Goals::Progress::Row>` (personal book; empty without one); partial `goals/_widget` (locals `rows:`, `business:`).

- [ ] **Step 1: Write the failing specs**

`spec/requests/goal_widgets_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Goal widgets" do
  let!(:household) { create(:household) }

  it "shows the book's active goals on its overview, linking to each report" do
    book = create(:business)
    goal = create(:goal, business: book, name: "Pay back Uncle Tony", target: "30,000")
    sign_in_as user_with_role("viewer", book)
    get business_path(book)
    widget = Nokogiri::HTML(response.body).at_css(".goal-widget")
    expect(widget.text).to include("Pay back Uncle Tony").and include("$0.00 of $30,000.00")
    expect(widget.at_css("a[href='#{business_goal_path(book, goal)}']")).to be_present
  end

  it "hides the widget when the book has no active goals" do
    book = create(:business)
    create(:goal, business: book, archived_at: Time.current)
    sign_in_as user_with_role("viewer", book)
    get business_path(book)
    expect(response.body).not_to include("goal-widget")
  end

  it "shows personal goals in the dashboard's Personal section, and not business goals" do
    owner = create(:user, :household_owner)
    studio = BusinessProvisioner.call(build(:business, person: create(:person, household:), name: "Studio"), owner:)
    personal = PersonalBookProvisioner.call(household)
    create(:goal, business: personal, name: "Truck fund", match_field: nil, match_operator: nil, match_value: nil)
    create(:goal, business: studio, name: "Business loan")
    sign_in_as owner
    get root_path
    widget = Nokogiri::HTML(response.body).at_css(".personal-summary .goal-widget")
    expect(widget.text).to include("Truck fund")
    expect(response.body).not_to include("Business loan")
  end
end
```

In `spec/models/household_dashboard_spec.rb` (its `let`s already define `owner`, `book` = the personal book, and `today`), add:

```ruby
  it "exposes the personal book's goal progress, and none without a personal book" do
    create(:goal, business: book, name: "Truck fund", match_field: nil, match_operator: nil, match_value: nil)
    create(:goal, business: studio, name: "Business loan")
    expect(described_class.new(user: owner, today:).goals.map { _1.goal.name }).to eq([ "Truck fund" ])
    book.destroy!
    expect(described_class.new(user: owner, today:).goals).to eq([])
  end
```

(If `book.destroy!` is blocked by restrict rules, drop those last two lines. The `@goals = []` default is still covered by the accountant example already in that file.)

- [ ] **Step 2: Run them to verify they fail**

Run: `bundle exec rspec spec/requests/goal_widgets_spec.rb spec/models/household_dashboard_spec.rb`
Expected: FAIL (no `.goal-widget`; `goals` undefined).

- [ ] **Step 3: Implement**

`app/views/goals/_widget.html.erb`:

```erb
<%# Active goals at a glance; each row opens the goal's report. Renders nothing when there are none. %>
<% if rows.any? %>
  <section class="card summary-card goal-widget">
    <header class="summary-card-header">
      <h2>Goals</h2>
      <span><%= link_to "All goals", business_goals_path(business) %> →</span>
    </header>
    <ul>
      <% rows.each do |row| %>
        <li><%= link_to row.goal.name, business_goal_path(business, row.goal) %><%= render "goals/bar", row: row %></li>
      <% end %>
    </ul>
  </section>
<% end %>
```

`app/controllers/businesses_controller.rb` `show`: add at the end, `@goals = Goals::Progress.for_book(@business)`.

`app/views/businesses/show.html.erb`: after the `tithes/summary` render line, add:

```erb
<%= render "goals/widget", rows: @goals, business: @business %>
```

`app/models/household_dashboard.rb`:
- add `:goals` to `attr_reader`
- in `initialize`, set `@goals = []` before `return unless @book`
- set `@goals = Goals::Progress.for_book(@book)` after the `@tithe =` line

`app/views/dashboards/show.html.erb`: inside `<section class="personal-summary">`, after the `tithes/summary` render line:

```erb
    <%= render "goals/widget", rows: @dashboard.goals, business: book %>
```

- [ ] **Step 4: Run the specs, rubocop, commit**

Run: `bundle exec rspec spec/requests/goal_widgets_spec.rb spec/models/household_dashboard_spec.rb spec/requests/household_dashboard_spec.rb spec/requests/businesses_spec.rb && bin/rubocop`
Expected: PASS.

```bash
git add app/views/goals/_widget.html.erb app/controllers/businesses_controller.rb app/views/businesses/show.html.erb app/models/household_dashboard.rb app/views/dashboards/show.html.erb spec/requests/goal_widgets_spec.rb spec/models/household_dashboard_spec.rb
git commit -m "Goals widget on the book overview and the dashboard's Personal section

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: System specs, demo seed, docs, PR

**Files:**
- Create: `spec/system/goals_spec.rb`
- Modify: `lib/demo_seeder.rb`, `spec/lib/demo_seeder_spec.rb`, `README.md` (only if it lists features per sub-project), `docs/roadmap.md`
- Test: `spec/system/goals_spec.rb`, `spec/lib/demo_seeder_spec.rb`

- [ ] **Step 1: Write the system specs**

`spec/system/goals_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Goals" do
  let!(:book) { create(:business) }
  let!(:checking) { create(:account, business: book, name: "Checking") }

  it "backfills a payment goal, shows it on the overview, and keeps an unlink" do
    create(:transaction, account: checking, posted_on: Date.new(2026, 2, 1), payee: "ZELLE TONY RUSSO", amount_cents: -1_500_00)
    create(:transaction, account: checking, posted_on: Date.new(2026, 3, 1), payee: "ZELLE TONY RUSSO", amount_cents: -2_000_00)
    system_sign_in_as user_with_role("editor", book)
    visit business_goals_path(book)
    click_on "New goal"
    fill_in "Name", with: "Pay back Uncle Tony"
    fill_in "Target", with: "30,000"
    fill_in "goal[match_value]", with: "tony"
    click_on "Save goal"
    expect(page).to have_content("Goal saved. 2 existing transactions linked.")

    visit business_path(book)
    within(".goal-widget") do
      expect(page).to have_content("$3,500.00 of $30,000.00")
      click_on "Pay back Uncle Tony"
    end
    within(".goal-transactions tbody tr:first-child") { click_on "Unlink" } # rack_test: no JS, so no confirm dialog
    expect(page).to have_content("Transaction unlinked.")
    expect(page).to have_content("$2,000.00 of $30,000.00")

    click_on "Edit"
    fill_in "goal[match_value]", with: "zelle"
    click_on "Save goal"
    expect(page).to have_content("Goal saved. 0 existing transactions linked.")
  end

  it "waterfalls two savings goals and flips the allocation on reorder", js: true do
    savings = create(:account, business: book, name: "Savings", kind: "savings", opening_balance: "8,000", opening_balance_on: Date.new(2026, 1, 1))
    nest = create(:goal, :savings, business: book, account: savings, name: "Nest egg", target: "6,000")
    truck = create(:goal, :savings, business: book, account: savings, name: "Truck", target: "10,000")
    system_sign_in_as user_with_role("editor", book)
    visit business_path(book)
    within(".goal-widget") do
      expect(page).to have_content("$6,000.00 of $6,000.00").and have_content("Met").and have_content("$2,000.00 of $10,000.00")
    end

    visit business_goals_path(book)
    handle = find("#goal_#{truck.id} .drag-handle").native
    target = find("#goal_#{nest.id}").native
    page.driver.browser.action.click_and_hold(handle).move_to(target, 0, -5).pause(duration: 0.2).move_to(target, 0, -10).release.perform
    expect(page).to have_css("tbody[data-sortable-state='saved']")
    visit business_path(book)
    within(".goal-widget") { expect(page).to have_content("$8,000.00 of $10,000.00").and have_content("$0.00 of $6,000.00") }
  end
end
```

- [ ] **Step 2: Run them**

Run: `memory_pressure | tail -1` (proceed only if free memory is OK), then `bundle exec rspec spec/system/goals_spec.rb`
Expected: PASS. If an expectation fails because of UI wording, fix the view or the spec so they agree with the spec document, not by loosening the assertion.

- [ ] **Step 3: Demo seed**

In `lib/demo_seeder.rb`:
- in `seed_personal`, after the line `add.(@today - 40, "TRANSFER FROM SAVINGS", …)`, add Tony payments to Joint Checking (before `seed_plaid` attaches it, so Plaid claims them like the other rows):

```ruby
    8.downto(1) { |months_ago| add.((@today << months_ago).beginning_of_month + 2, "ZELLE TO TONY RUSSO", -150_000, nil, transfer: true, categorized_by: "user") }
```

- add a new private method, called in `build` right after `seed_plaid(household, alex)`:

```ruby
  # Paying Uncle Tony back from Joint Checking, and a nest egg ahead of a truck fund in one savings account.
  def seed_goals(household)
    book = household.personal_book
    savings = book.accounts.create!(name: "Savings", source: "manual", kind: "savings",
                                    opening_balance: "10,000.00", opening_balance_on: @today - 120)
    savings.transactions.create!(posted_on: @today - 40, payee: "TRANSFER TO CHECKING", amount_cents: -200_000, transfer: true,
                                 categorized_by: "user")
    book.goals.create!(name: "Pay back Uncle Tony", kind: "payments", target: "30,000", target_date: @today.next_year.end_of_year,
                       match_field: "payee", match_operator: "contains", match_value: "tony")
    book.goals.create!(name: "Nest egg", kind: "savings", target: "6,000", account: savings)
    book.goals.create!(name: "Truck", kind: "savings", target: "10,000", account: savings)
  end
```

Call it as `seed_goals(household)`. The Tony payments are transfers, so the spending report and tithe stay as they were. The goal links them anyway, because goals ignore categorization.

`spec/lib/demo_seeder_spec.rb`: add, in the file's style:

```ruby
  it "seeds personal goals with progress" do
    # run the seeder the way the file's other examples do
    rows = Goals::Progress.for_book(Household.instance.personal_book).map { [ _1.goal.name, _1.saved_cents ] }
    expect(rows).to eq([ [ "Pay back Uncle Tony", 12_000_00 ], [ "Nest egg", 6_000_00 ], [ "Truck", 2_000_00 ] ])
  end
```

(If the seeder's `@today` makes fewer than 8 Tony payments land in the past, use `be > 0` for Tony and keep the savings figures exact.)

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb spec/db/seeds_spec.rb`
Expected: PASS.

- [ ] **Step 4: Docs**

`docs/roadmap.md`:
- Goals row: Size `10`, Status `In review (PR #N)` once the PR exists; until then `In progress`
- Documents table: add `[Goals](superpowers/plans/2026-10-14-goodbooks-goals.md)` in the Plan column of row 8
- Dependency graph: `○ 8 Goals` becomes `◐ 8 Goals` when the PR opens

`README.md`: if it has a feature list per sub-project, add one line: "Goals: payment goals matched like rules, savings goals filled in priority order from an account's balance, a dashboard widget and per-goal reports."

- [ ] **Step 5: Full verification**

Run: `bin/rails db:test:prepare && bundle exec rspec && bin/rubocop && bin/brakeman --no-pager -q && bin/bundler-audit && bin/importmap audit`
Expected: every command passes. RSpec shows `0 failures` with only the reporter output, and its example count is above the baseline.

- [ ] **Step 6: Commit, push, PR (controlling session)**

```bash
git add spec/system/goals_spec.rb lib/demo_seeder.rb spec/lib/demo_seeder_spec.rb docs/roadmap.md README.md
git commit -m "Goals system specs, demo goals, roadmap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin goals
```

Open the PR against `main` with `gh pr create`. The body has:
- **Summary:** a link to the spec, and one line per piece: balances, matcher, progress, pages, widget.
- **Acceptance testing:** the steps below, copied verbatim.
- The line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

Put the same acceptance steps in the Kaneo GB-11 description, move GB-11 to In Review, and update the roadmap status to `In review (PR #N)` in a follow-up commit.

**Acceptance testing (for the PR body and Kaneo):**

Setup: `bin/rails db:reset && bin/rails demo:seed && bin/dev`, then sign in as the demo household owner (credentials printed by `demo:seed`).

- [ ] **Dashboard → Personal:** a **Goals** card shows "Pay back Uncle Tony" (about $12,000 of $30,000), "Nest egg" $6,000 of $6,000 with a green **Met** badge, and "Truck" $2,000 of $10,000.
- [ ] Click **Pay back Uncle Tony**. The report lists the "ZELLE TO TONY RUSSO" payments, oldest first, with a running total that ends at the bar's amount.
- [ ] Click **Unlink** on the first payment and confirm. The total drops by $1,500.
- [ ] Click **Edit**, change the matcher text to `russo`, and save. The flash says how many were linked, and the unlinked payment stays unlinked.
- [ ] Click **Truck**. The allocation table shows Nest egg then Truck, and the history shows Savings' transactions with a running balance ending at $8,000.
- [ ] **Personal → Goals:** drag **Truck** above **Nest egg**. Back on the dashboard, Truck shows $8,000 of $10,000 and Nest egg $0 of $6,000. Drag it back.
- [ ] **Personal → Accounts:** the Balance column shows Savings at $8,000. Edit Savings and change the opening balance to $12,000. Nest egg and Truck now show $6,000 and $6,000.
- [ ] **New goal → Payments:** name "Groceries cap", target $500, matcher payee contains `kroger`, save. The flash reports the linked Kroger payments, and the report lists them.
- [ ] Archive "Groceries cap". It leaves the widget and appears under **Completed** on the Goals page. Unarchive it, and it comes back with the same payments.
- [ ] **Transactions:** edit any outflow, set **Goal** to "Pay back Uncle Tony", and save. The row shows a goal tag, and the goal's total rises.
- [ ] **Sound Roots Productions → Goals:** the page is empty, and the book's overview shows no Goals card. Create a payment goal there. It appears on that book's overview, not on the household dashboard.
- [ ] Sign in as the accountant (a viewer). The Goals page is visible with no **New goal**, drag handles, Edit or Unlink controls.
- [ ] Plaid accounts (Banks → Demo Bank → **Sync now**): the accounts list shows a Balance only for accounts the fake bank reports. The others show "—".
