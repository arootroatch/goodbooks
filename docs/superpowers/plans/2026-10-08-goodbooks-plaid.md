# goodbooks Plaid (Sub-project 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bank and card activity arrives automatically through Plaid: a book owner connects a bank with Plaid Link, assigns each Plaid account to a new account in a book they own (business or personal) or attaches it to an existing manual/CSV account, and posted transactions then sync daily, on Plaid's webhook, or on demand. They dedupe against CSV history in both directions, and bank-side removals/edits that would undo the user's work are flagged for review in the inbox.

**Architecture:** `PlaidGateway` is the only code that talks to Plaid (official `plaid` gem, loaded lazily) and returns plain hashes, so `FakePlaidGateway` (in `lib/`, no network) stands in for it in tests, in development without keys, and in `demo:seed`. App logic lives under the `PlaidFeed` namespace (never `Plaid`, which is the gem's): pure `TransactionMapper`, `ClaimMatcher`, and `WebhookVerifier`, plus the `Sync` and `Assignment` services. Plaid identity is stored in `transactions.plaid_transaction_id`, beside the CSV hash in `external_id`, so a row can carry both; each source *claims* the other's matching row (same amount, within 3 days, one-to-one) instead of inserting a duplicate.

**Tech Stack:** Ruby 4.0.7, Rails 8.1.4, SQLite, Hotwire (Turbo + Stimulus via importmap), Solid Queue, Active Record Encryption, RSpec, FactoryBot, Capybara (rack_test + headless Chrome), WebMock, `plaid` 52.0.0, `jwt` 3.3.0, Brakeman, bundler-audit, RuboCop (rails-omakase), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-08-goodbooks-plaid-design.md` (parent: `docs/superpowers/specs/2026-10-05-goodbooks-design.md` §3 cross-cutting rules; builds on the Invoices and Personal book specs).

## Prerequisites (before Task 1)

- `export PATH="$HOME/.rubies/ruby-4.0.7/bin:$PATH"` before every command (`ruby -v` → `ruby 4.0.7`).
- Work in the worktree `/Users/AlexRoot-Roatch/current-projects/goodbooks-plaid`, branch `plaid` (cut from `tithing`; holds the spec commit). Run `bundle install` once there.
- The PR's base is `tithing` (stacked on PR #7), not `main`.
- **Parallel branch:** `sales-tax` is built at the same time, also from `tithing`. Both touch `db/schema.rb`, `app/models/transaction.rb`, `spec/factories/transactions.rb`, `lib/demo_seeder.rb`, the dashboard, the inbox views, the README, and `docs/roadmap.md`. Keep every change to those files small and additive (new lines, new partials, new methods; no reformatting or reordering). Whichever of `sales-tax` / `plaid` merges second rebases onto the first and resolves the conflicts (for `db/schema.rb`: re-run `bin/rails db:migrate` and commit the regenerated file). Plaid migrations use the version prefix `20261009050…` so they can't collide with sales tax's.
- `bin/rails db:test:prepare && bundle exec rspec` → `661 examples, 0 failures` with no other output. This is the baseline; if it is not green, stop and report.

## Global Constraints

- Money is signed integer cents in `*_cents` columns; display with `money(cents)`. Never floats: Plaid's float amounts are converted with `BigDecimal(amount.to_s)` and must be whole cents.
- `Transaction#amount_cents`: positive = money into the account. Plaid reports outflows as positive, so the mapper negates.
- Never name an association, method, or local `transaction`. DB transactions use `ApplicationRecord.transaction` (or `with_lock`). Use `txn` for locals.
- App code that relates to Plaid lives in `PlaidGateway`, `FakePlaidGateway`, `PlaidItem`, `PlaidSyncJob`, `Plaid*Controller`, and the `PlaidFeed::` namespace. **Never define anything under `Plaid::`** (the gem's namespace; inside it, `Transaction` would resolve to `Plaid::Transaction`).
- Only `PlaidGateway` calls `require "plaid"`. The gem is in the Gemfile with `require: false`.
- `PlaidItem#access_token` is encrypted at rest, never rendered, never logged, never in a flash or `last_error`.
- WebMock keeps all real HTTP blocked in tests (`WebMock.disable_net_connect!(allow_localhost: true)` is already in `spec/rails_helper.rb`).
- Plaid disabled (`PlaidGateway.enabled?` false) → every Plaid route 404s, including the webhook; nav hides "Banks".
- Non-member → 404 (lookups through `Current.user.accessible_businesses`). Viewer writing → 403 (`require_editor!`). Plaid items: only `PlaidItem.manageable_by(Current.user)` (creator or household owner) → else 404. Assigning: only to `Current.user.owned_books` → else a row error.
- Strong params never list a `*_id` key (Brakeman). Assignment rows use the keys `plaid_account`, `choice`, `book`, `target`, `name`, `sync_from`.
- `config.action_controller.raise_on_missing_callback_actions = true` in test: every `only:`/`except:` list must name existing actions.
- Test output must stay clean: a passing `bundle exec rspec` prints only the reporter.
- TDD: each task writes its failing spec first and runs it to see it fail.
- Formatting: rails-omakase (`[ a, b ]` with inner spaces, double quotes). `bin/rubocop` must pass after every task.
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- Kaneo: the controlling session (not task implementers) comments progress on GB-5 ("Phase 5: Plaid", task id `tioo23drnv16xu66pl37y81d`, project GoodBooks, workspace Root User Projects) after each task, and moves it to In Review when the PR opens.

## Review Focus

1. **Plaid float amounts**: `1234.5`, `19.99`, `0.1`, and `-250.0` (a deposit) must become exactly `-123450`, `-1999`, `-10`, `25000`; `12.345` must raise instead of rounding. (Pinned in Task 3.)
2. **Identical amounts close together**: two $5.00 coffees on consecutive days, one already from CSV: Plaid claims exactly one row and inserts the other; a second sync claims nothing twice. (Pinned in Tasks 4 and 8.)
3. **Bank edits that collide with the user's work**: a `modified` event lowering an invoice-linked deposit below its allocations is flagged `changed_by_bank`, not a 500 and not a partial sync; a `modified` on an excluded row is ignored. (Pinned in Task 8.)
4. **Crafted assignment posts**: assigning to a book the user doesn't own, attaching an account in another person's book, attaching an already-linked or archived account, or a Plaid account id from another item → row errors, nothing applied. (Pinned in Task 12.)
5. **Webhook tampering and replay**: a valid token with a changed body, a token 6 minutes old, `alg: none`/HS256, and an expired key → 401; an unknown `item_id` with a valid signature → 200 and nothing enqueued. (Pinned in Tasks 7 and 14.)

## Spec decisions made while planning

- The app namespace is `PlaidFeed::` (spec: `Plaid::`), and the webhook controller is `PlaidWebhooksController`, because the `plaid` gem owns `Plaid::`.
- `PlaidGateway.current` holds the gateway (spec: `Rails.configuration.x.plaid_gateway`): a real gateway when `PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ENV` are all set; otherwise `FakePlaidGateway` in development and test, and `nil` (disabled) in production. Development without keys therefore shows a fake "Demo Bank", which is what makes the demo and acceptance testing work without Plaid keys.
- With the fake gateway, the Link button skips Plaid's script and posts a fake public token; with the real gateway it opens Plaid Link. The `js: true` system spec exercises the Stimulus controller through the fake path.
- `institution_name` uses `/item/get`'s `item.institution_name` (current Plaid responses include it), so `/institutions/get_by_id` is not needed.
- `modified` events update date, amount, and payee, never memo (users edit memos on imported rows).
- On the assignment page, a blank "sync from" date for an *attached* account means "after its latest existing transaction"; enter an early date (e.g. 2000-01-01) to import everything Plaid has. For a *new* account blank means no cutoff.
- The fake's key is generated per instance, so webhook specs sign with the same `FakePlaidGateway` instance they install as `PlaidGateway.current`.
- With Plaid disabled, item pages 404 like every other Plaid route (spec §11 also mentions a "Plaid is not configured" notice on the item page; the 404 rule wins, and existing Plaid accounts keep their data and show their last status on the accounts list).
- "Already synced from bank" matches only Plaid rows that have no CSV hash yet. A Plaid row that claimed a CSV row already has one, so re-importing that history in a different export format is out of scope (as it is without Plaid).
- `FakePlaidGateway` lists a fixed `DEMO_ACCOUNTS` set for the demo connection's access token in any process, so the demo item's page works in development.

## File Map

```
db/migrate/20261009050001_create_plaid_items.rb                 (Task 1)
db/migrate/20261009050002_add_plaid_to_accounts.rb              (Task 1)
db/migrate/20261009050003_add_plaid_to_transactions.rb          (Task 1)
db/migrate/20261009050004_add_synced_count_to_csv_imports.rb    (Task 10)
app/models/plaid_item.rb; account.rb, transaction.rb, user.rb (additions)        (Task 1, 9, 11)
app/controllers/transactions_controller.rb, csv_imports_controller.rb,
  csv_import_mappings_controller.rb; views/transactions/_form, accounts/index    (Task 2)
app/models/plaid_feed/transaction_mapper.rb                     pure (Task 3)
app/models/plaid_feed/claim_matcher.rb                          pure (Task 4)
app/models/plaid_gateway.rb; Gemfile                            (Task 5)
lib/fake_plaid_gateway.rb; spec/support/plaid.rb                (Task 6)
app/models/plaid_feed/webhook_verifier.rb                       pure (Task 7)
app/services/plaid_feed/sync.rb                                 (Task 8)
app/jobs/plaid_sync_job.rb; config/recurring.yml                (Task 9)
app/models/csv_import/preview.rb, csv_import.rb; views/csv_imports/show  (Task 10)
app/controllers/concerns/plaid_scoped.rb, plaid_items_controller.rb; views/plaid_items/*;
  app/javascript/controllers/plaid_link_controller.js; routes; layout nav; application_helper  (Task 11)
app/services/plaid_feed/assignment.rb, plaid_assignments_controller.rb; views/plaid_assignments/show  (Task 12)
app/controllers/plaid_reconnections_controller.rb; views/plaid_reconnections/new;
  views/plaid_items/_reconnect_banners; dashboards; accounts/_plaid_status    (Task 13)
app/controllers/plaid_webhooks_controller.rb                    (Task 14)
app/controllers/transaction_reviews_controller.rb; views/inboxes/_review*; household inbox;
  transaction_filter.rb; transactions/index; dashboards          (Task 15)
lib/demo_seeder.rb                                              (Task 16)
spec/system/plaid_connection_spec.rb, README.md, .env.example, docker-compose.yml  (Task 17)
```

---

### Task 1: Schema, `PlaidItem`, Plaid fields on accounts and transactions

**Files:**
- Create: `db/migrate/20261009050001_create_plaid_items.rb`, `db/migrate/20261009050002_add_plaid_to_accounts.rb`, `db/migrate/20261009050003_add_plaid_to_transactions.rb`, `app/models/plaid_item.rb`, `spec/factories/plaid_items.rb`, `spec/models/plaid_item_spec.rb`, `spec/models/account_plaid_spec.rb`, `spec/models/transaction_plaid_spec.rb`, `spec/models/user_owned_books_spec.rb`
- Modify: `app/models/account.rb`, `app/models/transaction.rb`, `app/models/user.rb`, `app/models/household.rb`, `spec/factories/accounts.rb`

**Interfaces:**
- Produces: `PlaidItem` (`household`, `created_by` (User), `institution_name`, `item_id`, `access_token` (encrypted), `cursor`, `status` enum `ok|login_required|error`, `last_synced_at`, `last_error`, `has_many :accounts`); `PlaidItem.manageable_by(user)` scope and `#manageable_by?(user)`; `Account#plaid_item`, `#plaid_account_id`, `#plaid_mask`, `#plaid_name`, `#plaid_sync_from`, `Account::CSV_IMPORTABLE_SOURCES = %w[csv plaid]`, scope `Account.csv_importable`, `#csv_importable?`; `Transaction#plaid_transaction_id`, `#review_reason`, `Transaction::REVIEW_REASONS` (hash reason → message), scope `Transaction.needs_review`, `#imported?`, `#review_message`; `User#owned_books` (active `Business` relation the user owns); factories `create(:plaid_item)`, `create(:account, :plaid)`.

- [ ] **Step 1: Write the failing specs**

`spec/models/plaid_item_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PlaidItem do
  it "encrypts the access token at rest and hides it from inspect" do
    item = create(:plaid_item, access_token: "access-sandbox-secret-123")
    raw = PlaidItem.connection.select_value("SELECT access_token FROM plaid_items WHERE id = #{item.id}")
    expect(raw).not_to include("access-sandbox-secret-123")
    expect(item.reload.access_token).to eq("access-sandbox-secret-123")
    expect(item.inspect).not_to include("access-sandbox-secret-123")
  end

  it "defaults to ok and validates status, item id, and institution" do
    item = create(:plaid_item)
    expect(item).to be_ok
    expect(build(:plaid_item, item_id: item.item_id)).not_to be_valid
    expect(build(:plaid_item, institution_name: "")).not_to be_valid
    expect { item.status = "bogus" }.not_to raise_error
    expect(item).not_to be_valid
  end

  it "is manageable by its creator and the household owner only" do
    creator = create(:user)
    owner = create(:user, :household_owner)
    other = create(:user)
    item = create(:plaid_item, created_by: creator)
    expect(PlaidItem.manageable_by(creator)).to eq([ item ])
    expect(PlaidItem.manageable_by(owner)).to eq([ item ])
    expect(PlaidItem.manageable_by(other)).to be_empty
    expect(item.manageable_by?(owner)).to be(true)
    expect(item.manageable_by?(other)).to be(false)
  end
end
```

`spec/models/account_plaid_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Account do
  it "needs a Plaid connection and account id when its source is plaid" do
    account = build(:account, source: "plaid")
    expect(account).not_to be_valid
    expect(account.errors[:source]).to include("plaid needs a Plaid connection")
    expect(build(:account, :plaid)).to be_valid
  end

  it "keeps Plaid link fields off non-Plaid accounts" do
    account = build(:account, :csv, plaid_item: create(:plaid_item), plaid_account_id: "acc-1")
    expect(account).not_to be_valid
    expect(account.errors[:source]).to include("must be plaid while linked to a Plaid connection")
  end

  it "links each Plaid account to one goodbooks account" do
    first = create(:account, :plaid)
    expect(build(:account, :plaid, plaid_account_id: first.plaid_account_id)).not_to be_valid
  end

  it "allows CSV upload on csv and plaid accounts only" do
    expect(build(:account, :csv)).to be_csv_importable
    expect(build(:account, :plaid)).to be_csv_importable
    expect(build(:account)).not_to be_csv_importable
    csv = create(:account, :csv)
    plaid = create(:account, :plaid)
    create(:account)
    expect(Account.csv_importable).to contain_exactly(csv, plaid)
  end
end
```

`spec/models/transaction_plaid_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Transaction do
  let(:account) { create(:account, :plaid) }

  it "is imported when it has a CSV hash or a Plaid id" do
    expect(build(:transaction, account: account)).not_to be_imported
    expect(build(:transaction, account: account, external_id: "abc")).to be_imported
    expect(build(:transaction, account: account, plaid_transaction_id: "p-1")).to be_imported
  end

  it "keeps Plaid ids unique per account" do
    create(:transaction, account: account, plaid_transaction_id: "p-1")
    expect { create(:transaction, account: account, plaid_transaction_id: "p-1") }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(create(:transaction, account: create(:account, :plaid), plaid_transaction_id: "p-1")).to be_persisted
  end

  it "flags rows for review with a known reason" do
    flagged = create(:transaction, account: account, review_reason: "removed_by_bank")
    create(:transaction, account: account)
    expect(Transaction.needs_review).to eq([ flagged ])
    expect(flagged.review_message).to eq("Removed by the bank")
    expect(build(:transaction, account: account, review_reason: "bogus")).not_to be_valid
  end
end
```

`spec/models/user_owned_books_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe User do
  it "lists the active books (business or personal) the user owns" do
    user = create(:user)
    owned = create(:business)
    personal = create(:business, :personal)
    edited = create(:business)
    archived = create(:business, archived_at: Time.current)
    create(:membership, user: user, business: owned, role: "owner")
    create(:membership, user: user, business: personal, role: "owner")
    create(:membership, user: user, business: edited, role: "editor")
    create(:membership, user: user, business: archived, role: "owner")
    expect(user.owned_books).to contain_exactly(owned, personal)
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/plaid_item_spec.rb spec/models/account_plaid_spec.rb spec/models/transaction_plaid_spec.rb spec/models/user_owned_books_spec.rb`
Expected: FAIL (`uninitialized constant PlaidItem`, unknown factory `plaid_item`, undefined `owned_books`).

- [ ] **Step 3: Migrations**

`db/migrate/20261009050001_create_plaid_items.rb`:

```ruby
class CreatePlaidItems < ActiveRecord::Migration[8.1]
  def change
    create_table :plaid_items do |t|
      t.references :household, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :institution_name, null: false
      t.string :item_id, null: false
      t.text :access_token, null: false
      t.text :cursor
      t.string :status, null: false, default: "ok"
      t.datetime :last_synced_at
      t.string :last_error
      t.timestamps
    end
    add_index :plaid_items, :item_id, unique: true
  end
end
```

`db/migrate/20261009050002_add_plaid_to_accounts.rb`:

```ruby
class AddPlaidToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounts, :plaid_item, foreign_key: true
    add_column :accounts, :plaid_account_id, :string
    add_column :accounts, :plaid_mask, :string
    add_column :accounts, :plaid_name, :string
    add_column :accounts, :plaid_sync_from, :date
    add_index :accounts, :plaid_account_id, unique: true, where: "plaid_account_id IS NOT NULL"
  end
end
```

`db/migrate/20261009050003_add_plaid_to_transactions.rb`:

```ruby
class AddPlaidToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :plaid_transaction_id, :string
    add_column :transactions, :review_reason, :string
    add_index :transactions, [ :account_id, :plaid_transaction_id ], unique: true, where: "plaid_transaction_id IS NOT NULL"
    add_index :transactions, :review_reason, where: "review_reason IS NOT NULL"
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare` (regenerates `db/schema.rb`).

- [ ] **Step 4: Models and factories**

`app/models/plaid_item.rb`:

```ruby
# One bank login connected through Plaid. Its accounts may feed different books.
class PlaidItem < ApplicationRecord
  belongs_to :household
  belongs_to :created_by, class_name: "User"
  has_many :accounts, dependent: :nullify

  encrypts :access_token

  enum :status, { ok: "ok", login_required: "login_required", error: "error" }, validate: true

  validates :institution_name, :item_id, :access_token, presence: true
  validates :item_id, uniqueness: true

  scope :manageable_by, ->(user) { user.household_owner? ? all : where(created_by: user) }

  def manageable_by?(user) = user.household_owner? || created_by_id == user.id
end
```

(`access_token` is already masked in `inspect` because `config.filter_parameters` contains `:token`, which `ActiveRecord::Base.filter_attributes` uses.)

`app/models/household.rb`: add `has_many :plaid_items, dependent: :destroy` under `has_many :businesses`.

`app/models/account.rb`: add below `has_many :csv_imports, dependent: :destroy`:

```ruby
  belongs_to :plaid_item, optional: true

  CSV_IMPORTABLE_SOURCES = %w[csv plaid].freeze
```

below `scope :active, ...`:

```ruby
  scope :csv_importable, -> { where(source: CSV_IMPORTABLE_SOURCES) }
```

below `validates :name, presence: true`:

```ruby
  validates :plaid_account_id, uniqueness: true, allow_nil: true
  validate :plaid_link_complete
```

below `def archived = archived?`:

```ruby
  def csv_importable? = CSV_IMPORTABLE_SOURCES.include?(source)

  private

  def plaid_link_complete
    linked = plaid_item_id.present? && plaid_account_id.present?
    if plaid? && !linked
      errors.add(:source, "plaid needs a Plaid connection")
    elsif !plaid? && (plaid_item_id.present? || plaid_account_id.present?)
      errors.add(:source, "must be plaid while linked to a Plaid connection")
    end
  end
```

`app/models/transaction.rb`: below `CATEGORIZED_BY = ...` add

```ruby
  REVIEW_REASONS = {
    "removed_by_bank" => "Removed by the bank",
    "changed_by_bank" => "The bank changed this transaction; your version was kept"
  }.freeze
```

below `scope :countable, ...` add

```ruby
  scope :needs_review, -> { where.not(review_reason: nil) }
```

below `validates :categorized_by, ...` add

```ruby
  validates :review_reason, inclusion: { in: REVIEW_REASONS.keys }, allow_nil: true
```

below `def categorized_by_user? = ...` add

```ruby
  def imported? = external_id.present? || plaid_transaction_id.present?

  def review_message = REVIEW_REASONS[review_reason]
```

`app/models/user.rb`: below `def membership_for(business)` method add

```ruby
  # Books (business or personal) this user can connect bank accounts to.
  def owned_books
    Business.active.where(id: memberships.owner.select(:business_id))
  end
```

`spec/factories/plaid_items.rb`:

```ruby
FactoryBot.define do
  factory :plaid_item do
    household { Household.first || association(:household) }
    created_by { association(:user) }
    institution_name { "Demo Bank" }
    sequence(:item_id) { |n| "item-#{n}" }
    sequence(:access_token) { |n| "access-sandbox-#{n}" }
  end
end
```

`spec/factories/accounts.rb`: add inside the factory, after `trait :csv`:

```ruby
    trait :plaid do
      source { "plaid" }
      plaid_item { association(:plaid_item, household: business.household) }
      sequence(:plaid_account_id) { |n| "plaid-account-#{n}" }
    end
```

- [ ] **Step 5: Run the specs to see them pass**

Run: `bundle exec rspec spec/models/plaid_item_spec.rb spec/models/account_plaid_spec.rb spec/models/transaction_plaid_spec.rb spec/models/user_owned_books_spec.rb`
Expected: PASS. Then `bundle exec rspec` → all green, and `bin/rubocop`.

- [ ] **Step 6: Commit**

```bash
git add db app/models spec/factories spec/models
git commit -m "Plaid: items, Plaid fields on accounts and transactions, owned books

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Read-only per row; CSV upload on Plaid-fed accounts

**Files:**
- Modify: `app/controllers/transactions_controller.rb`, `app/views/transactions/_form.html.erb`, `app/controllers/csv_imports_controller.rb:60`, `app/controllers/csv_import_mappings_controller.rb:37`, `app/views/accounts/index.html.erb:17`
- Test: `spec/requests/plaid_account_rows_spec.rb`

**Interfaces:**
- Consumes: `Transaction#imported?`, `Account.csv_importable`, `Account#csv_importable?`, factory trait `:plaid` (Task 1).

- [ ] **Step 1: Write the failing spec**

`spec/requests/plaid_account_rows_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Rows on Plaid-fed accounts" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, :plaid, business: business, name: "Checking") }
  let!(:manual_row) { create(:transaction, account: account, payee: "TYPED BY HAND", amount_cents: -1500) }
  let!(:bank_row) { create(:transaction, account: account, payee: "FROM PLAID", amount_cents: -2500, plaid_transaction_id: "p-1") }

  before { sign_in_as user_with_role("editor", business) }

  it "keeps a hand-entered row editable and deletable" do
    get edit_business_transaction_path(business, manual_row)
    expect(response.body).not_to include("(imported, read-only)")
    patch business_transaction_path(business, manual_row), params: { transaction: { payee: "FIXED", amount: "16.00", direction: "out" } }
    expect(manual_row.reload.payee).to eq("FIXED")
    expect(manual_row.amount_cents).to eq(-1600)
    delete business_transaction_path(business, manual_row)
    expect(Transaction.exists?(manual_row.id)).to be(false)
  end

  it "keeps a Plaid row's date, amount, and payee read-only" do
    get edit_business_transaction_path(business, bank_row)
    expect(response.body).to include("(imported, read-only)")
    patch business_transaction_path(business, bank_row), params: { transaction: { payee: "HACKED", amount: "1.00", memo: "note" } }
    expect(bank_row.reload.payee).to eq("FROM PLAID")
    expect(bank_row.amount_cents).to eq(-2500)
    expect(bank_row.memo).to eq("note")
    delete business_transaction_path(business, bank_row)
    expect(Transaction.exists?(bank_row.id)).to be(true)
  end

  it "offers CSV upload on a Plaid-fed account but not on a manual one" do
    get business_accounts_path(business)
    expect(response.body).to include(new_business_account_csv_import_path(business, account))
    get new_business_account_csv_import_path(business, account)
    expect(response).to have_http_status(:ok)
    cash = business.accounts.create!(name: "Petty", source: "manual", kind: "cash")
    get new_business_account_csv_import_path(business, cash)
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/requests/plaid_account_rows_spec.rb`
Expected: FAIL (manual row on a plaid account is treated as imported; CSV upload 404s on the plaid account).

- [ ] **Step 3: Implement**

`app/controllers/transactions_controller.rb`:
- in `update`, replace `permitted = @transaction.account.manual? ? MANUAL_EDITABLE : IMPORTED_EDITABLE` with `permitted = @transaction.imported? ? IMPORTED_EDITABLE : MANUAL_EDITABLE`;
- in `destroy`, replace `if !@transaction.account.manual?` with `if @transaction.imported?`.

`app/views/transactions/_form.html.erb`:
- line 3: `<% manual = transaction.new_record? || !transaction.imported? %>`
- the delete button condition: `<% if transaction.persisted? && !transaction.imported? %>`

`app/controllers/csv_imports_controller.rb` `set_account` and `app/controllers/csv_import_mappings_controller.rb` `set_import`: replace `@business.accounts.active.csv.find(params[:account_id])` with `@business.accounts.active.csv_importable.find(params[:account_id])`.

`app/views/accounts/index.html.erb`: replace `if account.csv? && !account.archived? && current_membership.can_edit?` with `if account.csv_importable? && !account.archived? && current_membership.can_edit?`.

- [ ] **Step 4: Run the specs**

Run: `bundle exec rspec spec/requests/plaid_account_rows_spec.rb spec/requests/transactions_spec.rb spec/requests/csv_imports_spec.rb`
Expected: PASS. Then `bundle exec rspec`, `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add app spec
git commit -m "Read-only per imported row; CSV upload stays available on Plaid accounts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Pure Plaid transaction mapper

**Files:**
- Create: `app/models/plaid_feed/transaction_mapper.rb`, `spec/models/plaid_feed/transaction_mapper_spec.rb`

**Interfaces:**
- Produces: `PlaidFeed::TransactionMapper.call(hash) → Row or nil` where the input hash has symbol keys `transaction_id, account_id, amount (Numeric), date (Date or ISO string), name, merchant_name, pending`; `PlaidFeed::TransactionMapper::Row` (`plaid_transaction_id, plaid_account_id, posted_on, amount_cents, payee, memo`) with `#attributes` → `{ plaid_transaction_id:, posted_on:, amount_cents:, payee:, memo: }`; `PlaidFeed::TransactionMapper::InvalidAmount` (StandardError).

- [ ] **Step 1: Write the failing spec**

`spec/models/plaid_feed/transaction_mapper_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PlaidFeed::TransactionMapper do
  def plaid(**overrides)
    { transaction_id: "t-1", account_id: "a-1", amount: 12.34, date: Date.new(2026, 10, 1),
      name: "SQ *JOES COFFEE 8475", merchant_name: "Joe's Coffee", pending: false }.merge(overrides)
  end

  it "inverts the sign: Plaid outflows are positive, the app's are negative" do
    expect(described_class.call(plaid(amount: 12.34)).amount_cents).to eq(-1234)
    expect(described_class.call(plaid(amount: -250.0)).amount_cents).to eq(25_000)
  end

  it "converts float amounts to exact cents" do
    { 1234.5 => -123_450, 19.99 => -1999, 0.1 => -10, 0.07 => -7, 1_000_000.01 => -100_000_001 }.each do |amount, cents|
      expect(described_class.call(plaid(amount: amount)).amount_cents).to eq(cents), amount.to_s
    end
  end

  it "raises on a fraction of a cent instead of rounding" do
    expect { described_class.call(plaid(amount: 12.345)) }.to raise_error(described_class::InvalidAmount, /12.345/)
  end

  it "uses the merchant name as payee and keeps the raw name as memo" do
    row = described_class.call(plaid)
    expect(row.payee).to eq("Joe's Coffee")
    expect(row.memo).to eq("SQ *JOES COFFEE 8475")
  end

  it "falls back to the name, then Unknown, and squishes whitespace" do
    row = described_class.call(plaid(merchant_name: nil, name: "  ACH   DEPOSIT  "))
    expect(row.payee).to eq("ACH DEPOSIT")
    expect(row.memo).to be_nil
    expect(described_class.call(plaid(merchant_name: "", name: "")).payee).to eq("Unknown")
    expect(described_class.call(plaid(merchant_name: "Kroger", name: "Kroger")).memo).to be_nil
  end

  it "skips pending transactions" do
    expect(described_class.call(plaid(pending: true))).to be_nil
  end

  it "accepts ISO date strings and returns the attributes to save" do
    row = described_class.call(plaid(date: "2026-10-02"))
    expect(row.posted_on).to eq(Date.new(2026, 10, 2))
    expect(row.plaid_account_id).to eq("a-1")
    expect(row.attributes).to eq(plaid_transaction_id: "t-1", posted_on: Date.new(2026, 10, 2), amount_cents: -1234,
                                 payee: "Joe's Coffee", memo: "SQ *JOES COFFEE 8475")
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/models/plaid_feed/transaction_mapper_spec.rb`
Expected: FAIL (`uninitialized constant PlaidFeed`).

- [ ] **Step 3: Implement**

`app/models/plaid_feed/transaction_mapper.rb`:

```ruby
module PlaidFeed
  # A Plaid transaction hash (from PlaidGateway or FakePlaidGateway) → transaction attributes. Pending → nil.
  module TransactionMapper
    class InvalidAmount < StandardError; end

    Row = Data.define(:plaid_transaction_id, :plaid_account_id, :posted_on, :amount_cents, :payee, :memo) do
      def attributes = { plaid_transaction_id:, posted_on:, amount_cents:, payee:, memo: }
    end

    def self.call(plaid)
      return nil if plaid[:pending]

      merchant = plaid[:merchant_name].to_s.squish.presence
      name = plaid[:name].to_s.squish.presence
      Row.new(
        plaid_transaction_id: plaid[:transaction_id],
        plaid_account_id: plaid[:account_id],
        posted_on: to_date(plaid[:date]),
        amount_cents: -cents(plaid[:amount]),
        payee: merchant || name || "Unknown",
        memo: (name if merchant && name && name != merchant)
      )
    end

    def self.cents(amount)
      cents = BigDecimal(amount.to_s) * 100
      raise InvalidAmount, "Plaid amount #{amount} is not a whole number of cents" unless cents.frac.zero?

      cents.to_i
    end

    def self.to_date(value) = value.is_a?(Date) ? value : Date.iso8601(value.to_s)

    private_class_method :cents, :to_date
  end
end
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec rspec spec/models/plaid_feed/transaction_mapper_spec.rb` → PASS; `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add app/models/plaid_feed spec/models/plaid_feed
git commit -m "Plaid: pure transaction mapper (sign, exact cents, payee, pending)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Pure claim matcher

**Files:**
- Create: `app/models/plaid_feed/claim_matcher.rb`, `spec/models/plaid_feed/claim_matcher_spec.rb`

**Interfaces:**
- Produces: `PlaidFeed::ClaimMatcher::WINDOW = 3`; `PlaidFeed::ClaimMatcher::Item = Data.define(:key, :posted_on, :amount_cents)`; `PlaidFeed::ClaimMatcher.call(incoming:, candidates:) → Hash{incoming key => candidate key}`. Incoming keys are unique strings; candidate keys are transaction ids (Integer). Used by `PlaidFeed::Sync` (Task 8) and `CsvImport::Preview` (Task 10).

- [ ] **Step 1: Write the failing spec**

`spec/models/plaid_feed/claim_matcher_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PlaidFeed::ClaimMatcher do
  def item(key, date, cents) = described_class::Item.new(key: key, posted_on: Date.parse(date), amount_cents: cents)
  def match(incoming, candidates) = described_class.call(incoming: incoming, candidates: candidates)

  it "pairs the same amount on the same day" do
    expect(match([ item("p1", "2026-10-05", -500) ], [ item(7, "2026-10-05", -500) ])).to eq("p1" => 7)
  end

  it "pairs up to three days apart in either direction, but not four" do
    expect(match([ item("p1", "2026-10-05", -500) ], [ item(7, "2026-10-08", -500) ])).to eq("p1" => 7)
    expect(match([ item("p1", "2026-10-05", -500) ], [ item(7, "2026-10-02", -500) ])).to eq("p1" => 7)
    expect(match([ item("p1", "2026-10-05", -500) ], [ item(7, "2026-10-09", -500) ])).to eq({})
  end

  it "never pairs different amounts or signs" do
    expect(match([ item("p1", "2026-10-05", -500) ], [ item(7, "2026-10-05", -501), item(8, "2026-10-05", 500) ])).to eq({})
  end

  it "prefers the nearest date, then the lowest id" do
    candidates = [ item(9, "2026-10-06", -500), item(8, "2026-10-04", -500), item(3, "2026-10-07", -500) ]
    expect(match([ item("p1", "2026-10-05", -500) ], candidates)).to eq("p1" => 8)
  end

  it "uses each candidate once, so two identical coffees pair one-to-one" do
    incoming = [ item("p1", "2026-10-05", -500), item("p2", "2026-10-06", -500) ]
    expect(match(incoming, [ item(7, "2026-10-05", -500) ])).to eq("p1" => 7)
    expect(match(incoming, [ item(7, "2026-10-05", -500), item(8, "2026-10-06", -500) ])).to eq("p1" => 7, "p2" => 8)
  end

  it "gives the closer incoming row the candidate when two compete" do
    incoming = [ item("far", "2026-10-02", -500), item("near", "2026-10-05", -500) ]
    expect(match(incoming, [ item(7, "2026-10-05", -500) ])).to eq("near" => 7)
  end

  it "handles empty inputs" do
    expect(match([], [ item(7, "2026-10-05", -500) ])).to eq({})
    expect(match([ item("p1", "2026-10-05", -500) ], [])).to eq({})
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/models/plaid_feed/claim_matcher_spec.rb`
Expected: FAIL (`uninitialized constant PlaidFeed::ClaimMatcher`).

- [ ] **Step 3: Implement**

`app/models/plaid_feed/claim_matcher.rb`:

```ruby
module PlaidFeed
  # Pairs incoming rows with existing rows from the other source: same amount, at most WINDOW days apart,
  # nearest date first, then lowest candidate key; each side is used at most once.
  module ClaimMatcher
    WINDOW = 3

    Item = Data.define(:key, :posted_on, :amount_cents)

    def self.call(incoming:, candidates:)
      by_amount = candidates.group_by(&:amount_cents)
      pairs = incoming.each_with_index.flat_map do |row, index|
        by_amount.fetch(row.amount_cents, []).filter_map do |candidate|
          days = (row.posted_on - candidate.posted_on).to_i.abs
          [ days, candidate.key, index, row.key ] if days <= WINDOW
        end
      end

      used = Set.new
      pairs.sort.each_with_object({}) do |(_, candidate_key, _, row_key), result|
        next if result.key?(row_key) || used.include?(candidate_key)

        used << candidate_key
        result[row_key] = candidate_key
      end
    end
  end
end
```

(`pairs.sort` orders by days, then candidate key, then incoming position; candidate keys are integers so the arrays compare cleanly.)

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec rspec spec/models/plaid_feed/claim_matcher_spec.rb` → PASS; `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add app/models/plaid_feed/claim_matcher.rb spec/models/plaid_feed/claim_matcher_spec.rb
git commit -m "Plaid: pure one-to-one claim matcher (same amount, within 3 days)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `PlaidGateway` over the `plaid` gem

**Files:**
- Modify: `Gemfile`, `Gemfile.lock`
- Create: `app/models/plaid_gateway.rb`, `spec/models/plaid_gateway_spec.rb`

**Interfaces:**
- Produces:
  - `PlaidGateway.new(client_id:, secret:, environment:)` (`environment` ∈ `"sandbox"`, `"production"`, else `ArgumentError`).
  - Instance methods (all return plain Ruby values): `fake? → false`; `create_link_token(user:, access_token: nil) → String`; `exchange_public_token(public_token) → { access_token:, item_id: }`; `institution_name(access_token) → String`; `accounts(access_token) → [{ account_id:, name:, mask:, type:, subtype: }]` (strings); `transactions_sync(access_token, cursor) → { added: [txn], modified: [txn], removed: [{ transaction_id:, account_id: }], next_cursor:, has_more: }` where txn = `{ transaction_id:, account_id:, amount:, date:, name:, merchant_name:, pending: }`; `item_remove(access_token) → nil`; `webhook_verification_key(kid) → Hash` with string keys (`"kty"`, `"crv"`, `"x"`, `"y"`, `"kid"`, `"alg"`, `"expired_at"`, …).
  - Errors: `PlaidGateway::Error` (`#code`), subclasses `LoginRequired`, `TransientError`, `MutationDuringPagination`.
  - Class methods: `PlaidGateway.current` (memoized `from_env`), `PlaidGateway.current=`, `PlaidGateway.reset!`, `PlaidGateway.enabled?`, `PlaidGateway.from_env(env = ENV, rails_env: Rails.env)`, `PlaidGateway.webhook_url` (`"https://APP_HOST/plaid/webhooks"` or nil).
  - `from_env` returns a `FakePlaidGateway` outside production when keys are missing; `FakePlaidGateway` is created in Task 6, so until then the spec stubs that branch.

- [ ] **Step 1: Add the gems**

In `Gemfile`, after `gem "csv"`:

```ruby
gem "plaid", "~> 52.0", require: false
gem "jwt", "~> 3.3"
```

Run: `bundle install` → `Gemfile.lock` gains `plaid (52.0.0)`, `jwt (3.3.0)`, `faraday (2.x)`. Run `bin/bundler-audit` → no vulnerabilities.

- [ ] **Step 2: Write the failing spec**

`spec/models/plaid_gateway_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PlaidGateway do
  subject(:gateway) { described_class.new(client_id: "client", secret: "secret", environment: "sandbox") }

  let(:base) { "https://sandbox.plaid.com" }
  let(:user) { create(:user) }

  def stub_plaid(path, body, status: 200)
    stub_request(:post, "#{base}#{path}").to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def plaid_error(code, type: "ITEM_ERROR")
    { error_type: type, error_code: code, error_message: "the message", display_message: nil, request_id: "r" }
  end

  it "rejects an unknown environment" do
    expect { described_class.new(client_id: "c", secret: "s", environment: "development") }.to raise_error(ArgumentError, /sandbox or production/)
  end

  it "creates a link token for transactions, or an update-mode token for an access token" do
    allow(described_class).to receive(:webhook_url).and_return("https://books.example.com/plaid/webhooks")
    stub_plaid("/link/token/create", { link_token: "link-sandbox-1", expiration: "2026-10-09T00:00:00Z", request_id: "r" })
    expect(gateway.create_link_token(user: user)).to eq("link-sandbox-1")
    expect(WebMock).to have_requested(:post, "#{base}/link/token/create").with { |req|
      body = JSON.parse(req.body)
      body["products"] == [ "transactions" ] && body["user"] == { "client_user_id" => user.id.to_s } &&
        body["webhook"] == "https://books.example.com/plaid/webhooks" && req.headers["Plaid-Client-Id"] == "client"
    }
    gateway.create_link_token(user: user, access_token: "access-1")
    expect(WebMock).to have_requested(:post, "#{base}/link/token/create").with { |req|
      body = JSON.parse(req.body)
      body["access_token"] == "access-1" && !body.key?("products")
    }
  end

  it "exchanges a public token and reads the institution name" do
    stub_plaid("/item/public_token/exchange", { access_token: "access-1", item_id: "item-1", request_id: "r" })
    stub_plaid("/item/get", { item: { item_id: "item-1", institution_id: "ins_1", institution_name: "First Platypus Bank" }, request_id: "r" })
    expect(gateway.exchange_public_token("public-1")).to eq(access_token: "access-1", item_id: "item-1")
    expect(gateway.institution_name("access-1")).to eq("First Platypus Bank")
  end

  it "lists accounts as plain hashes" do
    stub_plaid("/accounts/get", { accounts: [ { account_id: "a1", name: "Plaid Checking", mask: "0000", type: "depository",
                                                subtype: "checking", balances: {} } ], item: { item_id: "item-1" }, request_id: "r" })
    expect(gateway.accounts("access-1")).to eq([ { account_id: "a1", name: "Plaid Checking", mask: "0000", type: "depository", subtype: "checking" } ])
  end

  it "returns a sync page as plain hashes and sends the cursor and page size" do
    stub_plaid("/transactions/sync", {
      added: [ { transaction_id: "t1", account_id: "a1", amount: 12.34, date: "2026-10-01", name: "SQ *JOES", merchant_name: "Joes",
                 pending: false } ],
      modified: [], removed: [ { transaction_id: "t0", account_id: "a1" } ], next_cursor: "c2", has_more: true, request_id: "r"
    })
    page = gateway.transactions_sync("access-1", "c1")
    expect(page[:added]).to eq([ { transaction_id: "t1", account_id: "a1", amount: 12.34, date: Date.new(2026, 10, 1), name: "SQ *JOES",
                                   merchant_name: "Joes", pending: false } ])
    expect(page[:removed]).to eq([ { transaction_id: "t0", account_id: "a1" } ])
    expect(page.slice(:modified, :next_cursor, :has_more)).to eq(modified: [], next_cursor: "c2", has_more: true)
    expect(WebMock).to have_requested(:post, "#{base}/transactions/sync").with { |req|
      JSON.parse(req.body).slice("access_token", "cursor", "count") == { "access_token" => "access-1", "cursor" => "c1", "count" => 500 }
    }
  end

  it "omits a blank cursor on the first sync" do
    stub_plaid("/transactions/sync", { added: [], modified: [], removed: [], next_cursor: "c1", has_more: false, request_id: "r" })
    gateway.transactions_sync("access-1", nil)
    expect(WebMock).to have_requested(:post, "#{base}/transactions/sync").with { |req| !JSON.parse(req.body).key?("cursor") }
  end

  it "removes an item and fetches a webhook verification key" do
    stub_plaid("/item/remove", { request_id: "r" })
    stub_plaid("/webhook_verification_key/get", { key: { alg: "ES256", crv: "P-256", kid: "k1", kty: "EC", use: "sig", x: "x", y: "y",
                                                         created_at: 1, expired_at: nil }, request_id: "r" })
    expect(gateway.item_remove("access-1")).to be_nil
    expect(gateway.webhook_verification_key("k1")).to include("kid" => "k1", "kty" => "EC", "alg" => "ES256", "expired_at" => nil)
  end

  it "translates Plaid errors" do
    stub_plaid("/transactions/sync", plaid_error("ITEM_LOGIN_REQUIRED"), status: 400)
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::LoginRequired, "ITEM_LOGIN_REQUIRED: the message")

    stub_plaid("/transactions/sync", plaid_error("TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION", type: "TRANSACTIONS_ERROR"), status: 400)
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::MutationDuringPagination)

    stub_plaid("/transactions/sync", plaid_error("RATE_LIMIT", type: "RATE_LIMIT_EXCEEDED"), status: 429)
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::TransientError)

    stub_plaid("/transactions/sync", plaid_error("INTERNAL_SERVER_ERROR", type: "API_ERROR"), status: 500)
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::TransientError)

    stub_plaid("/transactions/sync", plaid_error("INVALID_ACCESS_TOKEN", type: "INVALID_INPUT"), status: 400)
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::Error) { |e|
      expect(e).not_to be_a(described_class::TransientError)
      expect(e.code).to eq("INVALID_ACCESS_TOKEN")
    }

    stub_request(:post, "#{base}/transactions/sync").to_timeout
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::TransientError)
  end

  describe ".from_env" do
    let(:keys) { { "PLAID_CLIENT_ID" => "c", "PLAID_SECRET" => "s", "PLAID_ENV" => "sandbox" } }

    it "builds a real gateway when all three keys are set" do
      expect(described_class.from_env(keys, rails_env: "production".inquiry)).to be_a(described_class)
    end

    it "is disabled in production without keys" do
      expect(described_class.from_env(keys.except("PLAID_SECRET"), rails_env: "production".inquiry)).to be_nil
    end

    it "builds the webhook URL from APP_HOST" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("APP_HOST").and_return("books.example.com")
      expect(described_class.webhook_url).to eq("https://books.example.com/plaid/webhooks")
      allow(ENV).to receive(:[]).with("APP_HOST").and_return(nil)
      expect(described_class.webhook_url).to be_nil
    end
  end
end
```

- [ ] **Step 3: Run it to see it fail**

Run: `bundle exec rspec spec/models/plaid_gateway_spec.rb`
Expected: FAIL (`uninitialized constant PlaidGateway`).

- [ ] **Step 4: Implement**

`app/models/plaid_gateway.rb`:

```ruby
# The only code that talks to Plaid. Returns plain hashes so FakePlaidGateway can stand in for it.
class PlaidGateway
  class Error < StandardError
    attr_reader :code

    def initialize(message = nil, code: nil)
      super(message)
      @code = code
    end
  end

  class LoginRequired < Error; end
  class TransientError < Error; end
  class MutationDuringPagination < Error; end

  ENVIRONMENTS = %w[sandbox production].freeze
  TRANSIENT_TYPES = %w[RATE_LIMIT_EXCEEDED API_ERROR INSTITUTION_ERROR].freeze
  SYNC_PAGE_SIZE = 500
  TIMEOUT_SECONDS = 30

  class << self
    def current
      @current = from_env unless defined?(@current)
      @current
    end

    attr_writer :current

    def reset!
      remove_instance_variable(:@current) if defined?(@current)
    end

    def enabled? = !current.nil?

    def from_env(env = ENV, rails_env: Rails.env)
      client_id, secret, environment = env.values_at("PLAID_CLIENT_ID", "PLAID_SECRET", "PLAID_ENV")
      if [ client_id, secret, environment ].all?(&:present?)
        new(client_id: client_id, secret: secret, environment: environment)
      elsif !rails_env.production?
        FakePlaidGateway.new
      end
    end

    def webhook_url
      host = ENV["APP_HOST"].presence
      host && "https://#{host}/plaid/webhooks"
    end
  end

  def initialize(client_id:, secret:, environment:)
    raise ArgumentError, "PLAID_ENV must be sandbox or production" unless ENVIRONMENTS.include?(environment)

    require "plaid"
    configuration = Plaid::Configuration.new
    configuration.server_index = Plaid::Configuration::Environment.fetch(environment)
    configuration.api_key["PLAID-CLIENT-ID"] = client_id
    configuration.api_key["PLAID-SECRET"] = secret
    configuration.timeout = TIMEOUT_SECONDS
    @api = Plaid::PlaidApi.new(Plaid::ApiClient.new(configuration))
  end

  def fake? = false

  def create_link_token(user:, access_token: nil)
    request = { user: { client_user_id: user.id.to_s }, client_name: "goodbooks", country_codes: [ "US" ], language: "en" }
    request[:webhook] = self.class.webhook_url if self.class.webhook_url
    if access_token
      request[:access_token] = access_token
    else
      request[:products] = [ "transactions" ]
    end
    call { @api.link_token_create(Plaid::LinkTokenCreateRequest.new(request)).link_token }
  end

  def exchange_public_token(public_token)
    response = call { @api.item_public_token_exchange(Plaid::ItemPublicTokenExchangeRequest.new(public_token: public_token)) }
    { access_token: response.access_token, item_id: response.item_id }
  end

  def institution_name(access_token)
    item = call { @api.item_get(Plaid::ItemGetRequest.new(access_token: access_token)).item }
    item.institution_name.presence || "Your bank"
  end

  def accounts(access_token)
    call { @api.accounts_get(Plaid::AccountsGetRequest.new(access_token: access_token)).accounts }.map do |account|
      { account_id: account.account_id, name: account.name, mask: account.mask, type: account.type.to_s, subtype: account.subtype.to_s }
    end
  end

  def transactions_sync(access_token, cursor)
    request = { access_token: access_token, count: SYNC_PAGE_SIZE }
    request[:cursor] = cursor if cursor.present?
    response = call { @api.transactions_sync(Plaid::TransactionsSyncRequest.new(request)) }
    {
      added: response.added.map { transaction_hash(_1) },
      modified: response.modified.map { transaction_hash(_1) },
      removed: response.removed.map { { transaction_id: _1.transaction_id, account_id: _1.account_id } },
      next_cursor: response.next_cursor,
      has_more: response.has_more
    }
  end

  def item_remove(access_token)
    call { @api.item_remove(Plaid::ItemRemoveRequest.new(access_token: access_token)) }
    nil
  end

  def webhook_verification_key(kid)
    key = call { @api.webhook_verification_key_get(Plaid::WebhookVerificationKeyGetRequest.new(key_id: kid)).key }
    key.to_hash.transform_keys(&:to_s)
  end

  private

  def transaction_hash(txn)
    { transaction_id: txn.transaction_id, account_id: txn.account_id, amount: txn.amount, date: txn.date,
      name: txn.name, merchant_name: txn.merchant_name, pending: txn.pending }
  end

  def call
    yield
  rescue Plaid::ApiError => e
    raise translate(e)
  end

  def translate(error)
    body = parse(error.response_body)
    code = body["error_code"].presence
    detail = body["error_message"].presence || (error.response_body.nil? ? error.message : "Plaid request failed")
    message = "#{code || "HTTP #{error.code || "error"}"}: #{detail}"
    error_class(code, body["error_type"], error.code).new(message, code: code)
  end

  def error_class(code, type, status)
    if code == "ITEM_LOGIN_REQUIRED" then LoginRequired
    elsif code == "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION" then MutationDuringPagination
    elsif status.to_i.zero? || status.to_i == 429 || status.to_i >= 500 || TRANSIENT_TYPES.include?(type) || code == "PRODUCT_NOT_READY"
      TransientError
    else Error
    end
  end

  def parse(raw)
    parsed = JSON.parse(raw.to_s)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
end
```

(Timeouts and connection failures reach `call` as `Plaid::ApiClient::ApiTimeoutError` / `ApiConnectionFailedError`, subclasses of `Plaid::ApiError` with no status, so they become `TransientError`.)

- [ ] **Step 5: Run it to see it pass**

Run: `bundle exec rspec spec/models/plaid_gateway_spec.rb` → PASS, with no warnings printed (if `require "plaid"` prints any, wrap it as `silence_warnings { require "plaid" }` and note it in the commit). Then `bundle exec rspec`, `bin/rubocop`, `bin/brakeman --no-pager`.

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock app/models/plaid_gateway.rb spec/models/plaid_gateway_spec.rb
git commit -m "Plaid: gateway over the plaid gem with error translation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `FakePlaidGateway` and the spec harness

**Files:**
- Create: `lib/fake_plaid_gateway.rb`, `spec/support/plaid.rb`, `spec/lib/fake_plaid_gateway_spec.rb`
- Modify: `spec/models/plaid_gateway_spec.rb` (add the fake-outside-production example)

**Interfaces:**
- Consumes: the `PlaidGateway` interface and error classes (Task 5).
- Produces: `FakePlaidGateway.new(accounts: FakePlaidGateway::DEFAULT_ACCOUNTS)` implementing every `PlaidGateway` instance method with the same return shapes, plus:
  - `fake? → true`
  - `FakePlaidGateway::KID`, `FakePlaidGateway::DEFAULT_ACCOUNTS` (three accounts: `fake-checking` depository/checking "Plaid Checking" mask 0000, `fake-savings` depository/savings "Plaid Saving" mask 1111, `fake-card` credit/credit card "Plaid Credit Card" mask 3333)
  - `FakePlaidGateway::DEMO_PUBLIC_TOKEN = "public-demo"` and `DEMO_ACCOUNTS` (`demo-operating` "Business Operating" 4821 checking, `demo-card` "Business Visa" 9034 credit, `demo-joint` "Joint Checking" 1177 checking): any fake instance, in any process, lists `DEMO_ACCOUNTS` for the access token that `DEMO_PUBLIC_TOKEN` exchanges to, so the demo item's page works in development
  - `FakePlaidGateway.access_token_for(public_token)` (deterministic)
  - `FakePlaidGateway.transaction(id, account_id:, amount:, date:, name:, merchant_name: nil, pending: false) → Hash` (Plaid sign: positive = money out)
  - scripting: `add_page(access_token, added: [], modified: [], removed: [])`, `fail_next(method_name, error)`, `expire_key!`, `sign_webhook(body, iat: Time.current.to_i, key: nil) → JWT String`, `calls` (method names in order)
  - cursor scheme: `nil` → first page; `next_cursor` is `"page-N"`; a cursor past the last page returns an empty page with the same cursor.
- `spec/support/plaid.rb`: before each example `PlaidGateway.current = FakePlaidGateway.new`; after each `PlaidGateway.reset!`; helper `plaid_gateway` returns the current fake.

- [ ] **Step 1: Write the failing spec**

`spec/lib/fake_plaid_gateway_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe FakePlaidGateway do
  subject(:fake) { described_class.new }

  it "is installed as the gateway in every example" do
    expect(PlaidGateway.current).to be_a(described_class)
    expect(PlaidGateway).to be_enabled
    expect(plaid_gateway).to be(PlaidGateway.current)
  end

  it "exchanges tokens deterministically and lists the default accounts" do
    first = fake.exchange_public_token("public-a")
    expect(first).to eq(fake.exchange_public_token("public-a"))
    expect(first[:access_token]).to start_with("access-fake-")
    expect(first[:item_id]).to start_with("item-fake-")
    expect(fake.institution_name(first[:access_token])).to eq("Demo Bank")
    expect(fake.accounts(first[:access_token]).map { _1[:account_id] }).to eq(%w[fake-checking fake-savings fake-card])
    expect(fake.create_link_token(user: build_stubbed(:user, id: 5))).to eq("link-fake-5")
    expect(fake.create_link_token(user: build_stubbed(:user, id: 5), access_token: "x")).to eq("link-fake-5-update")
  end

  it "lists the demo accounts for the demo connection in any instance" do
    token = fake.exchange_public_token(described_class::DEMO_PUBLIC_TOKEN)[:access_token]
    expect(token).to eq(described_class.access_token_for(described_class::DEMO_PUBLIC_TOKEN))
    expect(described_class.new.accounts(token).map { _1[:account_id] }).to eq(%w[demo-operating demo-card demo-joint])
  end

  it "serves scripted pages by cursor, then empty pages" do
    txn = described_class.transaction("t1", account_id: "fake-checking", amount: 5.0, date: Date.new(2026, 10, 1), name: "COFFEE")
    fake.add_page("access", added: [ txn ])
    fake.add_page("access", removed: [ { transaction_id: "t0", account_id: "fake-checking" } ])
    first = fake.transactions_sync("access", nil)
    expect(first).to eq(added: [ txn ], modified: [], removed: [], next_cursor: "page-1", has_more: true)
    second = fake.transactions_sync("access", "page-1")
    expect(second.slice(:next_cursor, :has_more)).to eq(next_cursor: "page-2", has_more: false)
    expect(fake.transactions_sync("access", "page-2")).to eq(added: [], modified: [], removed: [], next_cursor: "page-2", has_more: false)
    expect(fake.transactions_sync("other", nil)).to eq(added: [], modified: [], removed: [], next_cursor: "page-0", has_more: false)
  end

  it "raises scripted failures once, in order" do
    fake.fail_next(:transactions_sync, PlaidGateway::LoginRequired.new("ITEM_LOGIN_REQUIRED: login"))
    expect { fake.transactions_sync("access", nil) }.to raise_error(PlaidGateway::LoginRequired)
    expect { fake.transactions_sync("access", nil) }.not_to raise_error
    expect(fake.calls).to eq(%i[transactions_sync transactions_sync])
  end

  it "signs webhooks with a key it serves, and can expire that key" do
    token = fake.sign_webhook("{}")
    header = JWT.decode(token, nil, false).last
    expect(header).to include("alg" => "ES256", "kid" => described_class::KID)
    jwk = fake.webhook_verification_key(described_class::KID)
    payload, = JWT.decode(token, JWT::JWK.import(jwk.slice("kty", "crv", "x", "y").transform_keys(&:to_sym)).verify_key, true, algorithms: [ "ES256" ])
    expect(payload["request_body_sha256"]).to eq(Digest::SHA256.hexdigest("{}"))
    expect(jwk["expired_at"]).to be_nil
    fake.expire_key!
    expect(fake.webhook_verification_key(described_class::KID)["expired_at"]).to be_a(Integer)
    expect { fake.webhook_verification_key("other") }.to raise_error(PlaidGateway::Error)
  end
end
```

Add to `spec/models/plaid_gateway_spec.rb` inside `describe ".from_env"`:

```ruby
    it "uses the fake gateway outside production when keys are missing" do
      expect(described_class.from_env({}, rails_env: "development".inquiry)).to be_a(FakePlaidGateway)
    end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/lib/fake_plaid_gateway_spec.rb spec/models/plaid_gateway_spec.rb`
Expected: FAIL (`uninitialized constant FakePlaidGateway`, undefined `plaid_gateway`).

- [ ] **Step 3: Implement**

`lib/fake_plaid_gateway.rb`:

```ruby
# Stands in for PlaidGateway in tests, in development without Plaid keys, and in demo:seed. No network.
class FakePlaidGateway
  KID = "fake-plaid-key"
  DEFAULT_ACCOUNTS = [
    { account_id: "fake-checking", name: "Plaid Checking", mask: "0000", type: "depository", subtype: "checking" },
    { account_id: "fake-savings", name: "Plaid Saving", mask: "1111", type: "depository", subtype: "savings" },
    { account_id: "fake-card", name: "Plaid Credit Card", mask: "3333", type: "credit", subtype: "credit card" }
  ].freeze
  DEMO_PUBLIC_TOKEN = "public-demo"
  DEMO_ACCOUNTS = [
    { account_id: "demo-operating", name: "Business Operating", mask: "4821", type: "depository", subtype: "checking" },
    { account_id: "demo-card", name: "Business Visa", mask: "9034", type: "credit", subtype: "credit card" },
    { account_id: "demo-joint", name: "Joint Checking", mask: "1177", type: "depository", subtype: "checking" }
  ].freeze
  EMPTY_PAGE = { added: [], modified: [], removed: [] }.freeze

  attr_reader :calls

  # A Plaid-shaped transaction hash. Plaid's sign: positive amount = money out of the account.
  def self.transaction(id, account_id:, amount:, date:, name:, merchant_name: nil, pending: false)
    { transaction_id: id, account_id: account_id, amount: amount, date: date, name: name, merchant_name: merchant_name, pending: pending }
  end

  def self.access_token_for(public_token) = "access-fake-#{Digest::SHA256.hexdigest(public_token.to_s)[0, 12]}"

  def initialize(accounts: DEFAULT_ACCOUNTS)
    @accounts = accounts
    @pages = Hash.new { |hash, token| hash[token] = [] }
    @failures = Hash.new { |hash, name| hash[name] = [] }
    @calls = []
    @key = OpenSSL::PKey::EC.generate("prime256v1")
    @key_expired_at = nil
  end

  def fake? = true

  def add_page(access_token, added: [], modified: [], removed: [])
    @pages[access_token] << { added: added, modified: modified, removed: removed }
  end

  def fail_next(method_name, error)
    @failures[method_name] << error
  end

  def expire_key!
    @key_expired_at = Time.current.to_i
  end

  def sign_webhook(body, iat: Time.current.to_i, key: nil)
    JWT.encode({ iat: iat, request_body_sha256: Digest::SHA256.hexdigest(body) }, key || @key, "ES256", { kid: KID })
  end

  def create_link_token(user:, access_token: nil)
    record(:create_link_token) { "link-fake-#{user.id}#{"-update" if access_token}" }
  end

  def exchange_public_token(public_token)
    record(:exchange_public_token) do
      access_token = self.class.access_token_for(public_token)
      { access_token: access_token, item_id: access_token.sub("access-", "item-") }
    end
  end

  def institution_name(_access_token) = record(:institution_name) { "Demo Bank" }

  def accounts(access_token)
    record(:accounts) { (access_token == self.class.access_token_for(DEMO_PUBLIC_TOKEN) ? DEMO_ACCOUNTS : @accounts).map(&:dup) }
  end

  def transactions_sync(access_token, cursor)
    record(:transactions_sync) do
      pages = @pages[access_token]
      index = cursor.to_s.delete_prefix("page-").to_i
      if index < pages.size
        pages[index].merge(next_cursor: "page-#{index + 1}", has_more: index + 1 < pages.size)
      else
        EMPTY_PAGE.merge(next_cursor: cursor.presence || "page-0", has_more: false)
      end
    end
  end

  def item_remove(_access_token) = record(:item_remove) { nil }

  def webhook_verification_key(kid)
    record(:webhook_verification_key) do
      raise PlaidGateway::Error.new("INVALID_WEBHOOK_VERIFICATION_KEY_ID: unknown key", code: "INVALID_WEBHOOK_VERIFICATION_KEY_ID") unless kid == KID

      JWT::JWK.new(@key, kid: KID).export.transform_keys(&:to_s)
        .merge("alg" => "ES256", "use" => "sig", "created_at" => 1, "expired_at" => @key_expired_at)
    end
  end

  private

  def record(method_name)
    @calls << method_name
    failure = @failures[method_name].shift
    raise failure if failure

    yield
  end
end
```

`spec/support/plaid.rb`:

```ruby
module PlaidHelpers
  def plaid_gateway = PlaidGateway.current
end

RSpec.configure do |config|
  config.include PlaidHelpers
  config.before { PlaidGateway.current = FakePlaidGateway.new }
  config.after { PlaidGateway.reset! }
end
```

- [ ] **Step 4: Run them to see them pass**

Run: `bundle exec rspec spec/lib/fake_plaid_gateway_spec.rb spec/models/plaid_gateway_spec.rb` → PASS. Then `bundle exec rspec`, `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add lib/fake_plaid_gateway.rb spec/support/plaid.rb spec/lib/fake_plaid_gateway_spec.rb spec/models/plaid_gateway_spec.rb
git commit -m "Plaid: fake gateway for tests, demo, and keyless development

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Pure webhook verifier

**Files:**
- Create: `app/models/plaid_feed/webhook_verifier.rb`, `spec/models/plaid_feed/webhook_verifier_spec.rb`

**Interfaces:**
- Consumes: `PlaidGateway::Error` (Task 5); the `jwt` gem (Task 5).
- Produces: `PlaidFeed::WebhookVerifier.new(key_fetcher:, now: Time.current)` where `key_fetcher.call(kid)` returns a JWK hash with string keys (or nil); `#verify!(body:, token:) → true` or raises `PlaidFeed::WebhookVerifier::Invalid` (message says why); `MAX_AGE = 5.minutes`.

- [ ] **Step 1: Write the failing spec**

`spec/models/plaid_feed/webhook_verifier_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PlaidFeed::WebhookVerifier do
  let(:key) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:jwk) { JWT::JWK.new(key, kid: "k1").export.transform_keys(&:to_s).merge("alg" => "ES256", "expired_at" => nil) }
  let(:now) { Time.zone.parse("2026-10-08 12:00:00") }
  let(:body) { %({"webhook_type":"TRANSACTIONS","webhook_code":"SYNC_UPDATES_AVAILABLE","item_id":"item-1"}) }
  let(:verifier) { described_class.new(key_fetcher: ->(kid) { kid == "k1" ? jwk : nil }, now: now) }

  def token(signed_body: body, iat: now.to_i, signing_key: key, headers: { kid: "k1" })
    JWT.encode({ iat: iat, request_body_sha256: Digest::SHA256.hexdigest(signed_body) }, signing_key, "ES256", headers)
  end

  def invalid(token_value, message = nil)
    expect { verifier.verify!(body: body, token: token_value) }.to raise_error(described_class::Invalid, message)
  end

  it "accepts a fresh token from a current Plaid key whose hash matches the body" do
    expect(verifier.verify!(body: body, token: token)).to be(true)
    expect(verifier.verify!(body: body, token: token(iat: (now - 4.minutes).to_i))).to be(true)
  end

  it "rejects a missing or malformed token" do
    invalid(nil, /missing/)
    invalid("")
    invalid("not-a-jwt")
  end

  it "rejects any algorithm but ES256" do
    invalid(JWT.encode({ iat: now.to_i }, "secret", "HS256", { kid: "k1" }), /algorithm/)
    unsigned = [ { alg: "none", kid: "k1" }, { iat: now.to_i, request_body_sha256: Digest::SHA256.hexdigest(body) } ]
      .map { Base64.urlsafe_encode64(_1.to_json, padding: false) }.join(".") + "."
    invalid(unsigned, /algorithm/)
  end

  it "rejects a missing, unknown, or expired key" do
    invalid(token(headers: {}), /key id/)
    invalid(token(headers: { kid: "other" }), /unknown key/)
    jwk["expired_at"] = now.to_i - 60
    invalid(token, /expired key/)
  end

  it "rejects a signature from another key" do
    invalid(token(signing_key: OpenSSL::PKey::EC.generate("prime256v1")))
  end

  it "rejects a token issued more than five minutes ago, or without iat" do
    invalid(token(iat: (now - 6.minutes).to_i), /too old/)
    invalid(JWT.encode({ request_body_sha256: Digest::SHA256.hexdigest(body) }, key, "ES256", { kid: "k1" }))
  end

  it "rejects a body that was changed after signing" do
    invalid(token(signed_body: body.sub("item-1", "item-2")), /body hash/)
  end

  it "turns a key fetch failure into Invalid" do
    failing = described_class.new(key_fetcher: ->(_) { raise PlaidGateway::Error, "boom" }, now: now)
    expect { failing.verify!(body: body, token: token) }.to raise_error(described_class::Invalid, /boom/)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/models/plaid_feed/webhook_verifier_spec.rb`
Expected: FAIL (`uninitialized constant PlaidFeed::WebhookVerifier`).

- [ ] **Step 3: Implement**

`app/models/plaid_feed/webhook_verifier.rb`:

```ruby
module PlaidFeed
  # A Plaid webhook is genuine when its Plaid-Verification header is an ES256 JWT signed by a current Plaid key,
  # issued within MAX_AGE, whose request_body_sha256 claim matches the raw body.
  class WebhookVerifier
    MAX_AGE = 5.minutes

    class Invalid < StandardError; end

    def initialize(key_fetcher:, now: Time.current)
      @key_fetcher = key_fetcher
      @now = now
    end

    def verify!(body:, token:)
      raise Invalid, "missing Plaid-Verification header" if token.blank?

      header = JWT.decode(token, nil, false).last
      raise Invalid, "unexpected algorithm #{header["alg"].inspect}" unless header["alg"] == "ES256"
      raise Invalid, "missing key id" if header["kid"].blank?

      payload, = JWT.decode(token, verify_key(header["kid"]), true, algorithms: [ "ES256" ])
      raise Invalid, "token is too old" if Integer(payload["iat"]) < (@now - MAX_AGE).to_i

      digest = Digest::SHA256.hexdigest(body.to_s)
      raise Invalid, "body hash mismatch" unless ActiveSupport::SecurityUtils.secure_compare(digest, payload["request_body_sha256"].to_s)

      true
    rescue JWT::DecodeError, PlaidGateway::Error, ArgumentError, TypeError => e
      raise Invalid, e.message
    end

    private

    def verify_key(kid)
      jwk = @key_fetcher.call(kid)
      raise Invalid, "unknown key" if jwk.blank?
      raise Invalid, "expired key" if jwk["expired_at"].present?

      JWT::JWK.import(jwk.slice("kty", "crv", "x", "y").transform_keys(&:to_sym)).verify_key
    end
  end
end
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec rspec spec/models/plaid_feed/webhook_verifier_spec.rb` → PASS; `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add app/models/plaid_feed/webhook_verifier.rb spec/models/plaid_feed/webhook_verifier_spec.rb
git commit -m "Plaid: pure webhook verifier (ES256, key id, age, body hash)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `PlaidFeed::Sync`

**Files:**
- Create: `app/services/plaid_feed/sync.rb`, `spec/services/plaid_feed/sync_spec.rb`

**Interfaces:**
- Consumes: `PlaidFeed::TransactionMapper` (Task 3), `PlaidFeed::ClaimMatcher` (Task 4), gateway interface (Tasks 5–6), `RuleApplier.new(book).apply(transactions)`, `PlaidItem` / `Account` / `Transaction` Plaid fields (Task 1).
- Produces: `PlaidFeed::Sync.call(item, gateway: PlaidGateway.current) → PlaidFeed::Sync::Result` (`inserted, claimed, modified, flagged, excluded`, all Integers). Raises `PlaidGateway::Error` subclasses (from the gateway; after 3 restarts on mutation, `PlaidGateway::TransientError`) and `PlaidFeed::TransactionMapper::InvalidAmount`; on any raise nothing is written and the cursor is unchanged.

- [ ] **Step 1: Write the failing spec**

`spec/services/plaid_feed/sync_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PlaidFeed::Sync do
  let!(:book) { create(:business) }
  let!(:item) { create(:plaid_item, access_token: "access-1") }
  let!(:checking) { create(:account, :plaid, business: book, plaid_item: item, plaid_account_id: "acc-checking", name: "Checking") }

  def plaid(id, amount:, date:, name: "COFFEE SHOP", merchant_name: nil, pending: false, account_id: "acc-checking")
    FakePlaidGateway.transaction(id, account_id: account_id, amount: amount, date: Date.parse(date), name: name,
                                     merchant_name: merchant_name, pending: pending)
  end

  def page(**changes) = plaid_gateway.add_page("access-1", **changes)
  def sync = described_class.call(item.reload, gateway: plaid_gateway)

  it "inserts posted transactions with the app's sign, skips pending ones, and saves the cursor" do
    item.update!(status: "error", last_error: "old failure")
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01", name: "SQ *COFFEE 8475", merchant_name: "Coffee"),
                  plaid("t2", amount: 9.0, date: "2026-10-01", pending: true) ])
    result = sync
    txn = checking.transactions.sole
    expect(txn.attributes.slice("plaid_transaction_id", "posted_on", "amount_cents", "payee", "memo"))
      .to eq("plaid_transaction_id" => "t1", "posted_on" => Date.new(2026, 10, 1), "amount_cents" => -450,
             "payee" => "Coffee", "memo" => "SQ *COFFEE 8475")
    expect(result.inserted).to eq(1)
    expect(item.reload).to have_attributes(cursor: "page-1", status: "ok", last_error: nil)
    expect(item.last_synced_at).to be_present
  end

  it "skips transactions before the account's sync-from date" do
    checking.update!(plaid_sync_from: Date.new(2026, 10, 2))
    page(added: [ plaid("old", amount: 1.0, date: "2026-10-01"), plaid("new", amount: 2.0, date: "2026-10-02") ])
    sync
    expect(checking.transactions.pluck(:plaid_transaction_id)).to eq([ "new" ])
  end

  it "ignores Plaid accounts that aren't assigned" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01", account_id: "acc-unassigned") ])
    expect(sync.inserted).to eq(0)
    expect(Transaction.count).to eq(0)
  end

  it "claims a matching CSV row instead of inserting a duplicate, leaving the user's version alone" do
    software = create(:category, business: book, name: "Software")
    csv = create(:transaction, account: checking, posted_on: Date.new(2026, 10, 2), amount_cents: -450, payee: "SQ *COFFEE 123",
                               external_id: "hash-1", category: software, categorized_by: "user")
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01", merchant_name: "Coffee") ])
    result = sync
    expect(checking.transactions.count).to eq(1)
    expect(csv.reload).to have_attributes(plaid_transaction_id: "t1", payee: "SQ *COFFEE 123", posted_on: Date.new(2026, 10, 2),
                                          category: software, external_id: "hash-1")
    expect(result.claimed).to eq(1)
  end

  it "claims a hand-entered row too" do
    manual = create(:transaction, account: checking, posted_on: Date.new(2026, 10, 1), amount_cents: -450, payee: "coffee")
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01") ])
    sync
    expect(manual.reload.plaid_transaction_id).to eq("t1")
  end

  it "claims one-to-one: two identical coffees and one CSV row make two rows, and re-delivery adds nothing" do
    csv = create(:transaction, account: checking, posted_on: Date.new(2026, 10, 1), amount_cents: -500, payee: "COFFEE", external_id: "h")
    page(added: [ plaid("t1", amount: 5.0, date: "2026-10-01"), plaid("t2", amount: 5.0, date: "2026-10-02") ])
    sync
    expect(csv.reload.plaid_transaction_id).to eq("t1")
    expect(checking.transactions.pluck(:plaid_transaction_id)).to contain_exactly("t1", "t2")
    page(added: [ plaid("t2", amount: 5.0, date: "2026-10-02") ])
    sync
    expect(checking.transactions.count).to eq(2)
  end

  it "applies bank modifications to date, amount, and payee, but never the memo" do
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01", name: "PENDING NAME") ])
    sync
    checking.transactions.sole.update!(memo: "my note")
    page(modified: [ plaid("t1", amount: 5.25, date: "2026-10-03", name: "FINAL NAME") ])
    expect(sync.modified).to eq(1)
    expect(checking.transactions.sole).to have_attributes(posted_on: Date.new(2026, 10, 3), amount_cents: -525, payee: "FINAL NAME",
                                                          memo: "my note")
  end

  it "ignores modifications to an excluded row" do
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01") ])
    sync
    checking.transactions.sole.update!(excluded: true)
    page(modified: [ plaid("t1", amount: 99.0, date: "2026-10-01") ])
    sync
    expect(checking.transactions.sole.amount_cents).to eq(-450)
  end

  it "flags a modification the app's rules reject, keeping the user's version" do
    income = create(:category, :income, business: book, name: "Sales")
    page(added: [ plaid("d1", amount: -1200.0, date: "2026-10-01", name: "ACME PAYMENT") ])
    sync
    deposit = checking.transactions.sole
    deposit.update!(category: income, categorized_by: "user")
    invoice = create(:invoice, business: book, amount_cents: 120_000)
    expect(InvoicePayments.link(invoice: invoice, deposit: deposit)).to be_ok
    page(modified: [ plaid("d1", amount: -1000.0, date: "2026-10-01", name: "ACME PAYMENT") ])
    result = sync
    expect(result.flagged).to eq(1)
    expect(deposit.reload).to have_attributes(amount_cents: 120_000, review_reason: "changed_by_bank")
    expect(invoice.reload).to be_paid
  end

  describe "removals" do
    let!(:category) { create(:category, business: book) }

    before do
      page(added: %w[a b c d].map { plaid(_1, amount: 1.0, date: "2026-10-01") })
      sync
    end

    def row(id) = checking.transactions.find_by!(plaid_transaction_id: id)

    it "excludes untouched and rule-categorized rows, and flags rows the user categorized or linked" do
      rule = create(:rule, business: book, category: category)
      row("b").update!(category: category, categorized_by: "rule", rule: rule)
      row("c").update!(category: category, categorized_by: "user")
      income = create(:category, :income, business: book)
      row("d").update!(amount_cents: 120_000, category: income, categorized_by: "user")
      InvoicePayments.link(invoice: create(:invoice, business: book, amount_cents: 120_000), deposit: row("d"))
      page(removed: %w[a b c d x].map { { transaction_id: _1, account_id: "acc-checking" } })
      result = sync
      expect(row("a")).to have_attributes(excluded: true, review_reason: nil)
      expect(row("b")).to have_attributes(excluded: true, review_reason: nil)
      expect(row("c")).to have_attributes(excluded: false, review_reason: "removed_by_bank")
      expect(row("d")).to have_attributes(excluded: false, review_reason: "removed_by_bank")
      expect(result).to have_attributes(excluded: 2, flagged: 2)
    end
  end

  it "runs each book's rules on inserted rows only" do
    personal = create(:business, :personal)
    joint = create(:account, :plaid, business: personal, plaid_item: item, plaid_account_id: "acc-joint")
    software = create(:category, business: book, name: "Software")
    groceries = create(:category, business: personal, name: "Groceries")
    create(:rule, business: book, value: "adobe", category: software)
    create(:rule, business: personal, value: "kroger", category: groceries)
    claimed = create(:transaction, account: checking, posted_on: Date.new(2026, 10, 1), amount_cents: -5499, payee: "ADOBE OLD",
                                   external_id: "h")
    page(added: [ plaid("t1", amount: 54.99, date: "2026-10-01", name: "ADOBE"), plaid("t2", amount: 20.0, date: "2026-10-01", name: "ADOBE CC"),
                  plaid("t3", amount: 80.0, date: "2026-10-01", name: "KROGER", account_id: "acc-joint") ])
    sync
    expect(claimed.reload.category).to be_nil
    expect(checking.transactions.find_by!(plaid_transaction_id: "t2")).to have_attributes(category: software, categorized_by: "rule")
    expect(joint.transactions.sole).to have_attributes(category: groceries, categorized_by: "rule")
  end

  it "follows pagination to the last page" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01") ])
    page(added: [ plaid("t2", amount: 2.0, date: "2026-10-01") ])
    sync
    expect(checking.transactions.count).to eq(2)
    expect(item.reload.cursor).to eq("page-2")
  end

  it "restarts from the saved cursor when Plaid's data changes mid-sync" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01") ])
    plaid_gateway.fail_next(:transactions_sync, PlaidGateway::MutationDuringPagination.new("changed"))
    sync
    expect(checking.transactions.count).to eq(1)
    expect(plaid_gateway.calls.count(:transactions_sync)).to eq(2)
  end

  it "gives up as a transient error after three restarts, writing nothing" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01") ])
    4.times { plaid_gateway.fail_next(:transactions_sync, PlaidGateway::MutationDuringPagination.new("changed")) }
    expect { sync }.to raise_error(PlaidGateway::TransientError)
    expect(Transaction.count).to eq(0)
    expect(item.reload.cursor).to be_nil
  end

  it "writes nothing and keeps the cursor when a page can't be applied" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01"), plaid("t2", amount: 12.345, date: "2026-10-01") ])
    expect { sync }.to raise_error(PlaidFeed::TransactionMapper::InvalidAmount)
    expect(Transaction.count).to eq(0)
    expect(item.reload.cursor).to be_nil
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/services/plaid_feed/sync_spec.rb`
Expected: FAIL (`uninitialized constant PlaidFeed::Sync`).

- [ ] **Step 3: Implement**

`app/services/plaid_feed/sync.rb`:

```ruby
module PlaidFeed
  # Applies one item's Plaid changes to the books in a single DB transaction, then saves the new cursor.
  # Plaid rows claim matching CSV or hand-entered rows instead of duplicating them; bank changes that the
  # app's rules reject, or that would undo the user's work, flag the row for review instead.
  class Sync
    MAX_RESTARTS = 3

    Result = Data.define(:inserted, :claimed, :modified, :flagged, :excluded)

    def self.call(item, gateway: PlaidGateway.current) = new(item, gateway).call

    def initialize(item, gateway)
      @item = item
      @gateway = gateway
      @counts = Hash.new(0)
    end

    def call
      added, modified, removed, cursor = fetch
      ApplicationRecord.transaction do
        accounts = @item.accounts.includes(:business).where.not(plaid_account_id: nil).index_by(&:plaid_account_id)
        inserted = apply_added(added, accounts)
        modified.each { apply_modified(_1, accounts) }
        removed.each { apply_removed(_1, accounts) }
        inserted.group_by { _1.account.business }.each { |book, rows| RuleApplier.new(book).apply(rows) }
        @item.update!(cursor: cursor, last_synced_at: Time.current, status: "ok", last_error: nil)
      end
      Result.new(**Result.members.index_with { @counts[_1] })
    end

    private

    def fetch
      restarts = 0
      begin
        added, modified, removed = [], [], []
        cursor = @item.cursor
        loop do
          page = @gateway.transactions_sync(@item.access_token, cursor)
          added.concat(page[:added])
          modified.concat(page[:modified])
          removed.concat(page[:removed])
          cursor = page[:next_cursor]
          break unless page[:has_more]
        end
        [ added, modified, removed, cursor ]
      rescue PlaidGateway::MutationDuringPagination
        restarts += 1
        raise PlaidGateway::TransientError, "Plaid's data changed during the sync; it will be retried" if restarts > MAX_RESTARTS

        retry
      end
    end

    def apply_added(added, accounts)
      added.group_by { _1[:account_id] }.flat_map do |plaid_account_id, plaid_rows|
        account = accounts[plaid_account_id]
        next [] unless account

        rows = plaid_rows.filter_map { TransactionMapper.call(_1) }
        rows.reject! { |row| account.plaid_sync_from && row.posted_on < account.plaid_sync_from }
        known = account.transactions.where(plaid_transaction_id: rows.map(&:plaid_transaction_id)).index_by(&:plaid_transaction_id)
        fresh, repeated = rows.partition { known[_1.plaid_transaction_id].nil? }
        repeated.each { update_from_bank(known[_1.plaid_transaction_id], _1) }
        insert_or_claim(account, fresh)
      end
    end

    def insert_or_claim(account, rows)
      claims = claims_for(account, rows)
      rows.filter_map do |row|
        if (existing = claims[row.plaid_transaction_id])
          existing.update!(plaid_transaction_id: row.plaid_transaction_id)
          @counts[:claimed] += 1
          nil
        else
          @counts[:inserted] += 1
          account.transactions.create!(row.attributes)
        end
      end
    end

    def claims_for(account, rows)
      return {} if rows.empty?

      dates = rows.map(&:posted_on)
      candidates = account.transactions.where(plaid_transaction_id: nil)
        .where(posted_on: (dates.min - ClaimMatcher::WINDOW)..(dates.max + ClaimMatcher::WINDOW)).to_a
      pairs = ClaimMatcher.call(
        incoming: rows.map { ClaimMatcher::Item.new(key: _1.plaid_transaction_id, posted_on: _1.posted_on, amount_cents: _1.amount_cents) },
        candidates: candidates.map { ClaimMatcher::Item.new(key: _1.id, posted_on: _1.posted_on, amount_cents: _1.amount_cents) }
      )
      by_id = candidates.index_by(&:id)
      pairs.transform_values { by_id.fetch(_1) }
    end

    def apply_modified(plaid, accounts)
      account = accounts[plaid[:account_id]]
      row = account && TransactionMapper.call(plaid)
      txn = row && account.transactions.find_by(plaid_transaction_id: row.plaid_transaction_id)
      update_from_bank(txn, row) if txn
    end

    def update_from_bank(txn, row)
      return if txn.excluded?

      txn.assign_attributes(posted_on: row.posted_on, amount_cents: row.amount_cents, payee: row.payee)
      return unless txn.changed?

      if txn.save
        @counts[:modified] += 1
      else
        txn.restore_attributes
        txn.update!(review_reason: "changed_by_bank")
        @counts[:flagged] += 1
      end
    end

    def apply_removed(plaid, accounts)
      txn = Transaction.where(account: accounts.values).find_by(plaid_transaction_id: plaid[:transaction_id])
      return if txn.nil? || txn.excluded?

      if txn.categorized_by_user? || txn.invoice_payments.exists?
        txn.update!(review_reason: "removed_by_bank")
        @counts[:flagged] += 1
      else
        txn.update!(excluded: true)
        @counts[:excluded] += 1
      end
    end
  end
end
```

- [ ] **Step 4: Run it to see it pass**

Run: `bundle exec rspec spec/services/plaid_feed/sync_spec.rb` → PASS. Then `bundle exec rspec`, `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add app/services/plaid_feed spec/services/plaid_feed
git commit -m "Plaid: sync service (insert, claim, modify, remove, flag, rules, cursor)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: `PlaidSyncJob` and the daily schedule

**Files:**
- Create: `app/jobs/plaid_sync_job.rb`, `spec/jobs/plaid_sync_job_spec.rb`
- Modify: `app/models/plaid_item.rb`, `config/recurring.yml`, `spec/models/plaid_item_spec.rb`

**Interfaces:**
- Consumes: `PlaidFeed::Sync.call` (Task 8), gateway errors (Task 5).
- Produces: `PlaidSyncJob.perform_later(item)` (status updates on failure, retries transient errors 5 times, concurrency key `"PlaidSyncJob/PlaidItem/<id>"`); `PlaidItem.sync_all_later` (enqueues one job per `ok` item, no-op when Plaid is disabled).

- [ ] **Step 1: Write the failing specs**

`spec/jobs/plaid_sync_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PlaidSyncJob do
  let!(:item) { create(:plaid_item, access_token: "access-1") }
  let!(:account) { create(:account, :plaid, plaid_item: item, plaid_account_id: "acc-1") }

  it "syncs the item" do
    plaid_gateway.add_page("access-1", added: [ FakePlaidGateway.transaction("t1", account_id: "acc-1", amount: 1.0, date: Date.new(2026, 10, 1), name: "X") ])
    described_class.perform_now(item)
    expect(account.transactions.count).to eq(1)
  end

  it "marks the item login_required and does not retry" do
    plaid_gateway.fail_next(:transactions_sync, PlaidGateway::LoginRequired.new("ITEM_LOGIN_REQUIRED: log in again"))
    expect { described_class.perform_now(item) }.not_to have_enqueued_job(described_class)
    expect(item.reload).to have_attributes(status: "login_required", last_error: "ITEM_LOGIN_REQUIRED: log in again")
  end

  it "skips an item that needs reconnecting" do
    item.update!(status: "login_required")
    described_class.perform_now(item)
    expect(plaid_gateway.calls).to be_empty
  end

  it "retries transient errors, recording the last error, and marks the item errored when retries run out" do
    plaid_gateway.fail_next(:transactions_sync, PlaidGateway::TransientError.new("HTTP 500: down"))
    expect { described_class.perform_now(item) }.to have_enqueued_job(described_class).with(item)
    expect(item.reload).to have_attributes(status: "ok", last_error: "HTTP 500: down")

    plaid_gateway.fail_next(:transactions_sync, PlaidGateway::TransientError.new("HTTP 500: still down"))
    job = described_class.new(item)
    job.executions = 4
    job.perform_now
    expect(item.reload).to have_attributes(status: "error", last_error: "HTTP 500: still down")
  end

  it "marks the item errored on a permanent Plaid error or an unusable amount" do
    plaid_gateway.fail_next(:transactions_sync, PlaidGateway::Error.new("INVALID_ACCESS_TOKEN: bad"))
    described_class.perform_now(item)
    expect(item.reload).to have_attributes(status: "error", last_error: "INVALID_ACCESS_TOKEN: bad")

    item.update!(status: "ok")
    plaid_gateway.add_page("access-1", added: [ FakePlaidGateway.transaction("t1", account_id: "acc-1", amount: 1.005, date: Date.new(2026, 10, 1), name: "X") ])
    described_class.perform_now(item)
    expect(item.reload.status).to eq("error")
    expect(item.last_error).to include("not a whole number of cents")
  end

  it "does nothing when Plaid is disabled" do
    PlaidGateway.current = nil
    expect { described_class.perform_now(item) }.not_to raise_error
  end

  it "never runs two syncs of the same item at once" do
    expect(described_class.new(item).concurrency_key).to eq("PlaidSyncJob/PlaidItem/#{item.id}")
    expect(described_class.concurrency_limit).to eq(1)
  end
end
```

Add to `spec/models/plaid_item_spec.rb`:

```ruby
  it "enqueues a sync for every connected item, and nothing when Plaid is disabled" do
    ok = create(:plaid_item)
    create(:plaid_item, status: "login_required")
    create(:plaid_item, status: "error")
    expect { PlaidItem.sync_all_later }.to have_enqueued_job(PlaidSyncJob).with(ok).exactly(:once)
    PlaidGateway.current = nil
    expect { PlaidItem.sync_all_later }.not_to have_enqueued_job(PlaidSyncJob)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/jobs/plaid_sync_job_spec.rb spec/models/plaid_item_spec.rb`
Expected: FAIL (`uninitialized constant PlaidSyncJob`, undefined `sync_all_later`).

- [ ] **Step 3: Implement**

`app/jobs/plaid_sync_job.rb`:

```ruby
class PlaidSyncJob < ApplicationJob
  limits_concurrency to: 1, key: ->(item) { item }

  retry_on PlaidGateway::TransientError, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.arguments.first.update!(status: "error", last_error: error.message)
  end

  def perform(item)
    return if item.login_required? || !PlaidGateway.enabled?

    PlaidFeed::Sync.call(item)
  rescue PlaidGateway::LoginRequired => e
    item.update!(status: "login_required", last_error: e.message)
  rescue PlaidGateway::TransientError => e
    item.update!(last_error: e.message)
    raise
  rescue PlaidGateway::Error, PlaidFeed::TransactionMapper::InvalidAmount => e
    item.update!(status: "error", last_error: e.message)
  end
end
```

`app/models/plaid_item.rb`: add below the `manageable_by` scope:

```ruby
  def self.sync_all_later
    return unless PlaidGateway.enabled?

    ok.find_each { PlaidSyncJob.perform_later(_1) }
  end
```

`config/recurring.yml`: add under `production:` (after `database_backup`):

```yaml
  plaid_sync:
    command: "PlaidItem.sync_all_later"
    schedule: every day at 4am
```

- [ ] **Step 4: Run them to see them pass**

Run: `bundle exec rspec spec/jobs/plaid_sync_job_spec.rb spec/models/plaid_item_spec.rb` → PASS. Then `bundle exec rspec`, `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/plaid_sync_job.rb app/models/plaid_item.rb config/recurring.yml spec/jobs spec/models/plaid_item_spec.rb
git commit -m "Plaid: sync job with retries, item status, and a daily schedule

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: CSV import recognizes rows already synced from the bank

**Files:**
- Create: `db/migrate/20261009050004_add_synced_count_to_csv_imports.rb`, `spec/fixtures/files/plaid_overlap.csv`, `spec/models/csv_import_plaid_spec.rb`
- Modify: `app/models/csv_import/preview.rb`, `app/models/csv_import.rb`, `app/controllers/csv_imports_controller.rb` (`commit` notice), `app/views/csv_imports/show.html.erb`

**Interfaces:**
- Consumes: `PlaidFeed::ClaimMatcher` (Task 4), `Account.csv_importable` (Task 2).
- Produces: `CsvImport::Preview::Entry#match` (the Plaid-synced `Transaction` for `:synced` entries, else nil); entry status `:synced`; `CsvImport::Preview#synced_entries`; `csv_imports.synced_count`.

- [ ] **Step 1: Write the failing spec**

`spec/fixtures/files/plaid_overlap.csv`:

```
Date,Description,Amount
10/02/2026,KROGER #123 NASHVILLE,-82.15
10/03/2026,SHELL OIL 5551,-40.00
```

`spec/models/csv_import_plaid_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "CSV import on a Plaid-fed account" do
  let!(:account) do
    create(:account, :plaid, csv_mapping: CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount",
                                                                 date_format: "MM/DD/YYYY").to_h)
  end
  let!(:synced) { create(:transaction, account: account, posted_on: Date.new(2026, 10, 1), amount_cents: -8215, payee: "Kroger", plaid_transaction_id: "p-1") }

  def import
    upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/plaid_overlap.csv"), "text/csv")
    account.csv_imports.create!(file: upload)
  end

  it "previews a row Plaid already brought in as synced, next to its match" do
    preview = import.preview
    expect(preview.entries.map(&:status)).to eq(%i[synced new])
    expect(preview.synced_entries.sole.match).to eq(synced)
    expect(preview.new_entries.sole.row.payee).to eq("SHELL OIL 5551")
  end

  it "skips synced rows on commit, stamps them with the CSV hash, and treats a re-import as duplicates" do
    first = import
    first.commit!
    expect(account.transactions.count).to eq(2)
    expect(first.reload).to have_attributes(new_count: 1, synced_count: 1, duplicate_count: 0)
    expect(synced.reload.external_id).to be_present
    expect(synced.payee).to eq("Kroger")

    again = import
    expect(again.preview.entries.map(&:status)).to eq(%i[duplicate duplicate])
  end

  it "doesn't match a Plaid row that already carries a CSV hash" do
    synced.update!(external_id: "from-another-file")
    expect(import.preview.entries.map(&:status)).to eq(%i[new new])
  end
end
```

Add to `spec/requests/csv_imports_spec.rb` (inside its top-level `describe "CSV imports"`, which defines `business`):

```ruby
  it "says how many rows were already synced from the bank" do
    sign_in_as user_with_role("editor", business)
    plaid_account = create(:account, :plaid, business: business, csv_mapping: CsvImport::Mapping.new(
      date_column: "Date", payee_column: "Description", amount_column: "Amount", date_format: "MM/DD/YYYY"
    ).to_h)
    create(:transaction, account: plaid_account, posted_on: Date.new(2026, 10, 1), amount_cents: -8215, payee: "Kroger", plaid_transaction_id: "p-1")
    upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/plaid_overlap.csv"), "text/csv")
    csv_import = plaid_account.csv_imports.create!(file: upload)
    get business_account_csv_import_path(business, plaid_account, csv_import)
    expect(response.body).to include("1 already synced from the bank", "Already synced from bank")
    post commit_business_account_csv_import_path(business, plaid_account, csv_import)
    expect(flash[:notice]).to include("1 already synced from the bank")
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/models/csv_import_plaid_spec.rb spec/requests/csv_imports_spec.rb`
Expected: FAIL (statuses are `%i[new new]`; unknown attribute `synced_count`).

- [ ] **Step 3: Implement**

`db/migrate/20261009050004_add_synced_count_to_csv_imports.rb`:

```ruby
class AddSyncedCountToCsvImports < ActiveRecord::Migration[8.1]
  def change
    add_column :csv_imports, :synced_count, :integer, null: false, default: 0
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`.

`app/models/csv_import/preview.rb` (whole file):

```ruby
class CsvImport::Preview
  Entry = Data.define(:row, :status, :proposed_rule, :match) do
    def initialize(row:, status:, proposed_rule:, match: nil) = super
  end

  attr_reader :entries

  def self.build(csv_import)
    account = csv_import.account
    rows = CsvImport::Parser.new(csv_import.effective_mapping, account_id: account.id).parse(csv_import.content)
    existing = account.transactions.where(external_id: rows.filter_map(&:external_id)).pluck(:external_id).to_set
    synced = synced_matches(account, rows.select { _1.valid? && !existing.include?(_1.external_id) })
    rules = account.business.rules.applicable.ordered.includes(:category).to_a

    new(rows.map do |row|
      if !row.valid? then Entry.new(row:, status: :error, proposed_rule: nil)
      elsif existing.include?(row.external_id) then Entry.new(row:, status: :duplicate, proposed_rule: nil)
      elsif synced.key?(row.external_id) then Entry.new(row:, status: :synced, proposed_rule: nil, match: synced[row.external_id])
      else Entry.new(row:, status: :new, proposed_rule: RuleEngine.match(row.rule_attributes, rules))
      end
    end)
  end

  # Rows Plaid already brought in (no CSV hash yet): same amount within a few days, one-to-one.
  def self.synced_matches(account, rows)
    return {} if rows.empty?

    dates = rows.map(&:posted_on)
    window = PlaidFeed::ClaimMatcher::WINDOW
    candidates = account.transactions.where(external_id: nil).where.not(plaid_transaction_id: nil)
      .where(posted_on: (dates.min - window)..(dates.max + window)).to_a
    return {} if candidates.empty?

    item = PlaidFeed::ClaimMatcher::Item
    pairs = PlaidFeed::ClaimMatcher.call(
      incoming: rows.map { item.new(key: _1.external_id, posted_on: _1.posted_on, amount_cents: _1.amount_cents) },
      candidates: candidates.map { item.new(key: _1.id, posted_on: _1.posted_on, amount_cents: _1.amount_cents) }
    )
    by_id = candidates.index_by(&:id)
    pairs.transform_values { by_id.fetch(_1) }
  end
  private_class_method :synced_matches

  def initialize(entries)
    @entries = entries
  end

  def new_entries = entries.select { _1.status == :new }
  def duplicate_entries = entries.select { _1.status == :duplicate }
  def synced_entries = entries.select { _1.status == :synced }
  def error_entries = entries.select { _1.status == :error }
end
```

`app/models/csv_import.rb` `commit!`: after the `RuleApplier.new(account.business).apply(created)` line add

```ruby
      result.synced_entries.each { _1.match.update!(external_id: _1.row.external_id) }
```

and add `synced_count: result.synced_entries.size` to the final `update!(...)` call.

`app/controllers/csv_imports_controller.rb` `commit`: build the notice so the synced clause appears only when non-zero:

```ruby
  def commit
    @import.commit!
    synced = @import.synced_count.positive? ? ", #{@import.synced_count} already synced from the bank" : ""
    redirect_to business_transactions_path(@business, account_id: @account.id),
      notice: "Imported #{@import.new_count} new transactions (#{@import.duplicate_count} duplicates skipped#{synced}, " \
              "#{@import.error_count} rows with errors)."
  rescue CsvImport::NotPreviewed, CsvImport::Parser::FileError => e
```

(The `rescue` lines below stay as they are.)

`app/views/csv_imports/show.html.erb`:
- in the counts paragraph, after the duplicate line add `<%= " · #{@preview.synced_entries.size} already synced from the bank" if @preview.synced_entries.any? %>`;
- replace the status cell with:

```erb
          <td>
            <% case entry.status %>
            <% when :error %><%= entry.row.error %>
            <% when :synced %>Already synced from bank (<%= entry.match.posted_on %> · <%= entry.match.payee %> · <%= money(entry.match.amount_cents) %>)
            <% else %><%= entry.status %>
            <% end %>
          </td>
```

- [ ] **Step 4: Run them to see them pass**

Run: `bundle exec rspec spec/models/csv_import_plaid_spec.rb spec/requests/csv_imports_spec.rb spec/models/csv_import_spec.rb spec/system/csv_import_spec.rb` → PASS. Then `bundle exec rspec`, `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add db app/models/csv_import.rb app/models/csv_import app/controllers/csv_imports_controller.rb app/views/csv_imports spec
git commit -m "CSV import: skip rows already synced from the bank and stamp them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Connect a bank: items, Link, sync now, remove

**Files:**
- Create: `app/controllers/concerns/plaid_scoped.rb`, `app/controllers/plaid_items_controller.rb`, `app/helpers/plaid_items_helper.rb`, `app/views/plaid_items/index.html.erb`, `app/views/plaid_items/new.html.erb`, `app/views/plaid_items/show.html.erb`, `app/views/plaid_items/_link.html.erb`, `app/javascript/controllers/plaid_link_controller.js`, `spec/requests/plaid_items_spec.rb`
- Modify: `config/routes.rb`, `app/models/plaid_item.rb`, `app/helpers/application_helper.rb`, `app/views/layouts/application.html.erb`

**Interfaces:**
- Consumes: `PlaidGateway.current`/`.enabled?`, `FakePlaidGateway#fake?` (Tasks 5–6), `User#owned_books`, `PlaidItem.manageable_by` (Task 1), `PlaidSyncJob` (Task 9).
- Produces:
  - Routes: `plaid_items_path`, `new_plaid_item_path`, `plaid_item_path(item)`, `sync_plaid_item_path(item)` (POST).
  - `PlaidScoped` concern: `before_action :require_plaid!`; private `gateway`, `require_book_owner!`, `require_connections_access!`, `set_item` (`@item` from `params[:plaid_item_id] || params[:id]` through `PlaidItem.manageable_by(Current.user)`).
  - `PlaidItem#disconnect!(gateway) → warning String or nil`.
  - Helpers: `show_bank_connections?` (ApplicationHelper), `plaid_status_label(item)`, `book_label(business)` (PlaidItemsHelper).
  - Partial `plaid_items/_link` (locals `token:`, `url:`, `label:`) and Stimulus controller `plaid-link` (values `token` String, `fake` Boolean; targets `form`, `publicToken`, `status`; action `open`).

- [ ] **Step 1: Write the failing spec**

`spec/requests/plaid_items_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Plaid items" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business) }
  let!(:owner) { user_with_role("owner", business) }

  it "404s every Plaid screen when Plaid is disabled" do
    item = create(:plaid_item, created_by: owner)
    sign_in_as owner
    PlaidGateway.current = nil
    [ plaid_items_path, new_plaid_item_path, plaid_item_path(item) ].each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
    end
    get root_path
    expect(response.body).not_to include(plaid_items_path)
  end

  it "lets a book owner open Link and shows Banks in the nav" do
    sign_in_as owner
    get root_path
    expect(response.body).to include(plaid_items_path)
    get new_plaid_item_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="plaid-link"', "link-fake-#{owner.id}", 'data-plaid-link-fake-value="true"')
  end

  it "404s connecting for a user who owns no book" do
    editor = user_with_role("editor", business)
    sign_in_as editor
    get new_plaid_item_path
    expect(response).to have_http_status(:not_found)
    post plaid_items_path, params: { public_token: "public-x" }
    expect(response).to have_http_status(:not_found)
    get plaid_items_path
    expect(response).to have_http_status(:not_found)
  end

  it "exchanges the public token and creates the item" do
    sign_in_as owner
    expect { post plaid_items_path, params: { public_token: "public-x" } }.to change(PlaidItem, :count).by(1)
    item = PlaidItem.last
    expect(item).to have_attributes(household: household, created_by: owner, institution_name: "Demo Bank", status: "ok")
    expect(item.access_token).to start_with("access-fake-")
    expect(response).to redirect_to(plaid_item_path(item))
  end

  it "reports a missing token or a Plaid failure without creating anything" do
    sign_in_as owner
    post plaid_items_path, params: { public_token: "" }
    expect(response).to redirect_to(new_plaid_item_path)
    plaid_gateway.fail_next(:exchange_public_token, PlaidGateway::Error.new("INVALID_PUBLIC_TOKEN: expired"))
    post plaid_items_path, params: { public_token: "public-x" }
    expect(flash[:alert]).to eq("Plaid: INVALID_PUBLIC_TOKEN: expired")
    expect(PlaidItem.count).to eq(0)
  end

  describe "an existing item" do
    let!(:item) { create(:plaid_item, created_by: owner, access_token: "access-1") }
    let!(:account) do
      create(:account, :plaid, business: business, plaid_item: item, plaid_account_id: "fake-checking", plaid_name: "Plaid Checking",
                               plaid_mask: "0000", name: "Operating")
    end

    it "is visible to its creator and the household owner, and 404 for other book owners" do
      sign_in_as owner
      get plaid_item_path(item)
      expect(response.body).to include("Demo Bank", "Operating", "····0000")
      get plaid_items_path
      expect(response.body).to include(plaid_item_path(item))

      sign_in_as create(:user, :household_owner)
      get plaid_item_path(item)
      expect(response).to have_http_status(:ok)

      sign_in_as user_with_role("owner", create(:business))
      get plaid_item_path(item)
      expect(response).to have_http_status(:not_found)
    end

    it "marks an account Plaid no longer reports" do
      account.update!(plaid_account_id: "gone")
      sign_in_as owner
      get plaid_item_path(item)
      expect(response.body).to include("No longer reported by the bank")
    end

    it "never renders the access token" do
      sign_in_as owner
      get plaid_item_path(item)
      expect(response.body).not_to include("access-1")
    end

    it "starts a sync" do
      sign_in_as owner
      expect { post sync_plaid_item_path(item) }.to have_enqueued_job(PlaidSyncJob).with(item)
      expect(response).to redirect_to(plaid_item_path(item))
    end

    it "removes the connection, keeping the account and its transactions" do
      account.update!(csv_mapping: { "date_column" => "Date" })
      manual_account = create(:account, :plaid, business: business, plaid_item: item, plaid_account_id: "fake-card")
      txn = create(:transaction, account: account, plaid_transaction_id: "t1")
      sign_in_as owner
      delete plaid_item_path(item)
      expect(response).to redirect_to(plaid_items_path)
      expect(flash[:notice]).to eq("Connection removed.")
      expect(PlaidItem.exists?(item.id)).to be(false)
      expect(account.reload).to have_attributes(source: "csv", plaid_item_id: nil, plaid_account_id: nil, plaid_sync_from: nil)
      expect(manual_account.reload.source).to eq("manual")
      expect(txn.reload.plaid_transaction_id).to eq("t1")
      expect(plaid_gateway.calls).to include(:item_remove)
    end

    it "removes the connection locally even when Plaid fails" do
      plaid_gateway.fail_next(:item_remove, PlaidGateway::Error.new("ITEM_NOT_FOUND: gone"))
      sign_in_as owner
      delete plaid_item_path(item)
      expect(flash[:notice]).to eq("Connection removed here. Plaid reported: ITEM_NOT_FOUND: gone")
      expect(PlaidItem.exists?(item.id)).to be(false)
    end
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/requests/plaid_items_spec.rb`
Expected: FAIL (`undefined local variable or method 'plaid_items_path'`).

- [ ] **Step 3: Routes, concern, model method, helpers**

`config/routes.rb`: after `resource :personal_book, only: :create` add

```ruby
  resources :plaid_items, only: %i[index new create show destroy] do
    post :sync, on: :member
  end
```

`app/controllers/concerns/plaid_scoped.rb`:

```ruby
# Plaid screens 404 unless Plaid is configured. Items are visible only to their creator and the household owner.
module PlaidScoped
  extend ActiveSupport::Concern

  included do
    before_action :require_plaid!
  end

  private

  def gateway = PlaidGateway.current

  def require_plaid!
    head :not_found unless PlaidGateway.enabled?
  end

  def require_book_owner!
    head :not_found unless Current.user.owned_books.exists?
  end

  def require_connections_access!
    head :not_found unless Current.user.household_owner? || Current.user.owned_books.exists?
  end

  def set_item
    @item = PlaidItem.manageable_by(Current.user).find(params[:plaid_item_id] || params[:id])
  end
end
```

`app/models/plaid_item.rb`: add below `manageable_by?`:

```ruby
  # Stops the feed: tells Plaid (best effort), turns the accounts back into CSV or manual ones, keeps every transaction.
  def disconnect!(gateway)
    warning = begin
      gateway.item_remove(access_token)
      nil
    rescue PlaidGateway::Error => e
      e.message
    end
    ApplicationRecord.transaction do
      accounts.each do |account|
        account.update!(source: account.csv_mapping.present? ? "csv" : "manual", plaid_item: nil, plaid_account_id: nil,
                        plaid_mask: nil, plaid_name: nil, plaid_sync_from: nil)
      end
      destroy!
    end
    warning
  end
```

`app/helpers/application_helper.rb`: add

```ruby
  def show_bank_connections?
    PlaidGateway.enabled? && (Current.user.household_owner? || Current.user.owned_books.exists?)
  end
```

`app/helpers/plaid_items_helper.rb`:

```ruby
module PlaidItemsHelper
  STATUS_LABELS = { "ok" => "Connected", "login_required" => "Needs reconnecting", "error" => "Error" }.freeze

  def plaid_status_label(item) = STATUS_LABELS.fetch(item.status)

  def book_label(business) = business.personal? ? "Personal" : business.name
end
```

`app/views/layouts/application.html.erb`: after the `Invites` link add

```erb
          <%= link_to "Banks", plaid_items_path if show_bank_connections? %>
```

- [ ] **Step 4: Controller, views, Stimulus**

`app/controllers/plaid_items_controller.rb`:

```ruby
class PlaidItemsController < ApplicationController
  include PlaidScoped

  before_action :require_connections_access!, only: :index
  before_action :require_book_owner!, only: %i[new create]
  before_action :set_item, only: %i[show sync destroy]

  def index
    @items = PlaidItem.manageable_by(Current.user).includes(accounts: :business).order(:institution_name)
  end

  def new
    @link_token = gateway.create_link_token(user: Current.user)
  rescue PlaidGateway::Error => e
    redirect_to plaid_items_path, alert: "Plaid: #{e.message}"
  end

  def create
    public_token = params[:public_token].to_s
    return redirect_to(new_plaid_item_path, alert: "Plaid didn't return a connection. Try again.") if public_token.blank?

    exchanged = gateway.exchange_public_token(public_token)
    item = PlaidItem.create!(household: Household.instance, created_by: Current.user, item_id: exchanged[:item_id],
                             access_token: exchanged[:access_token], institution_name: institution_name(exchanged[:access_token]))
    redirect_to plaid_item_path(item), notice: "Connected #{item.institution_name}."
  rescue PlaidGateway::Error => e
    redirect_to new_plaid_item_path, alert: "Plaid: #{e.message}"
  end

  def show
    @plaid_accounts = gateway.accounts(@item.access_token)
  rescue PlaidGateway::Error => e
    @gateway_error = e.message
  end

  def sync
    PlaidSyncJob.perform_later(@item)
    redirect_to plaid_item_path(@item), notice: "Sync started."
  end

  def destroy
    warning = @item.disconnect!(gateway)
    notice = warning ? "Connection removed here. Plaid reported: #{warning}" : "Connection removed."
    redirect_to plaid_items_path, notice: notice, status: :see_other
  end

  private

  # The item exists at Plaid once the token is exchanged, so a failed name lookup must not lose it.
  def institution_name(access_token)
    gateway.institution_name(access_token)
  rescue PlaidGateway::Error
    "Your bank"
  end
end
```

`app/views/plaid_items/index.html.erb`:

```erb
<h1>Bank connections</h1>
<% if @items.any? %>
  <table>
    <thead><tr><th>Bank</th><th>Status</th><th>Last synced</th><th>Accounts</th></tr></thead>
    <tbody>
      <% @items.each do |item| %>
        <tr id="<%= dom_id(item) %>">
          <td><%= link_to item.institution_name, plaid_item_path(item) %></td>
          <td><%= plaid_status_label(item) %></td>
          <td><%= item.last_synced_at ? "#{time_ago_in_words(item.last_synced_at)} ago" : "Never" %></td>
          <td><%= item.accounts.map { "#{book_label(_1.business)} › #{_1.name}" }.join(", ").presence || "None assigned" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% else %>
  <p>No banks connected yet.</p>
<% end %>
<%= link_to "Connect a bank", new_plaid_item_path if Current.user.owned_books.exists? %>
```

`app/views/plaid_items/new.html.erb`:

```erb
<h1>Connect a bank</h1>
<p>Plaid opens in a window to sign in to your bank. Afterwards you choose which book each account feeds.</p>
<%= render "plaid_items/link", token: @link_token, url: plaid_items_path, label: "Connect with Plaid" %>
```

`app/views/plaid_items/_link.html.erb`:

```erb
<% fake = PlaidGateway.current.fake? %>
<div data-controller="plaid-link" data-plaid-link-token-value="<%= token %>" data-plaid-link-fake-value="<%= fake %>">
  <% if fake %>
    <p>Plaid isn't configured here, so this connects a fake "Demo Bank".</p>
  <% end %>
  <%= form_with url: url, data: { plaid_link_target: "form" } do %>
    <%= hidden_field_tag :public_token, "", id: nil, data: { plaid_link_target: "publicToken" } %>
  <% end %>
  <button type="button" data-action="plaid-link#open"><%= label %></button>
  <p data-plaid-link-target="status" role="status"></p>
</div>
```

`app/views/plaid_items/show.html.erb`:

```erb
<h1><%= @item.institution_name %></h1>
<p>
  Status: <%= plaid_status_label(@item) %>
  <%= " · Last synced #{time_ago_in_words(@item.last_synced_at)} ago" if @item.last_synced_at %>
</p>
<% if @item.last_error.present? %>
  <p class="errors"><%= @item.last_error %></p>
<% end %>
<% if @gateway_error %>
  <p class="errors">Couldn't reach Plaid: <%= @gateway_error %></p>
<% end %>
<h2>Accounts</h2>
<% reported = @plaid_accounts&.map { _1[:account_id] } %>
<table>
  <thead><tr><th>Bank account</th><th>Feeds</th></tr></thead>
  <tbody>
    <% @item.accounts.includes(:business).order(:name).each do |account| %>
      <tr id="<%= dom_id(account) %>">
        <td><%= account.plaid_name %> ····<%= account.plaid_mask %></td>
        <td>
          <%= link_to "#{book_label(account.business)} › #{account.name}", business_transactions_path(account.business, account_id: account.id) %>
          <%= " · No longer reported by the bank" if reported && !reported.include?(account.plaid_account_id) %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
<%= button_to "Sync now", sync_plaid_item_path(@item) %>
<%= button_to "Remove connection", plaid_item_path(@item), method: :delete,
      data: { turbo_confirm: "Stop syncing #{@item.institution_name}? Transactions already imported stay." } %>
<p><%= link_to "All bank connections", plaid_items_path %></p>
```

`app/javascript/controllers/plaid_link_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

const PLAID_SCRIPT = "https://cdn.plaid.com/link/v2/stable/link-initialize.js"

// Opens Plaid Link and posts the public token it returns. With the fake gateway it skips Plaid and posts a fake token.
export default class extends Controller {
  static targets = ["form", "publicToken", "status"]
  static values = { token: String, fake: Boolean }

  async open() {
    if (this.fakeValue) return this.submit(`public-fake-${Date.now()}`)

    try {
      await this.loadScript()
      window.Plaid.create({
        token: this.tokenValue,
        onSuccess: (publicToken) => this.submit(publicToken),
        onExit: (error) => {
          if (error) this.statusTarget.textContent = error.display_message || error.error_message || "Plaid closed with an error."
        }
      }).open()
    } catch {
      this.statusTarget.textContent = "Couldn't load Plaid. Check your connection and try again."
    }
  }

  submit(publicToken) {
    this.publicTokenTarget.value = publicToken
    this.formTarget.requestSubmit()
  }

  loadScript() {
    if (window.Plaid) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = PLAID_SCRIPT
      script.onload = resolve
      script.onerror = reject
      document.head.appendChild(script)
    })
  }
}
```

(`pin_all_from "app/javascript/controllers"` already picks the controller up; no importmap change.)

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/requests/plaid_items_spec.rb` → PASS. Then `bundle exec rspec`, `bin/rubocop`, `bin/brakeman --no-pager`.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app spec/requests/plaid_items_spec.rb
git commit -m "Plaid: connect a bank with Link, item page, sync now, remove

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Assign Plaid accounts to books

**Files:**
- Create: `app/services/plaid_feed/assignment.rb`, `app/controllers/plaid_assignments_controller.rb`, `app/views/plaid_assignments/show.html.erb`, `spec/services/plaid_feed/assignment_spec.rb`, `spec/requests/plaid_assignments_spec.rb`
- Modify: `config/routes.rb`, `app/controllers/plaid_items_controller.rb` (`create` redirect), `app/views/plaid_items/show.html.erb`, `spec/requests/plaid_items_spec.rb` (redirect expectation)

**Interfaces:**
- Consumes: `PlaidScoped` (Task 11), `User#owned_books` (Task 1), gateway `accounts` (Tasks 5–6), `PlaidSyncJob` (Task 9).
- Produces: `PlaidFeed::Assignment.call(item:, user:, plaid_accounts:, rows:) → Result` (`errors` Hash plaid_account_id → message; `ok?`); `PlaidFeed::Assignment.kind_for(type, subtype) → "checking"|"savings"|"credit"|"other"`; rows are hash-likes with keys `plaid_account`, `choice` (`skip`|`new`|`attach`), `book`, `target`, `name`, `sync_from`. Route `plaid_item_assignment_path(item)` (GET show, PATCH update).

- [ ] **Step 1: Write the failing specs**

`spec/services/plaid_feed/assignment_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PlaidFeed::Assignment do
  let!(:user) { create(:user) }
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:personal) { create(:business, :personal) }
  let!(:item) { create(:plaid_item, created_by: user) }
  let(:plaid_accounts) { FakePlaidGateway::DEFAULT_ACCOUNTS }

  before do
    create(:membership, user: user, business: business, role: "owner")
    create(:membership, user: user, business: personal, role: "owner")
  end

  def assign(*rows) = described_class.call(item: item, user: user, plaid_accounts: plaid_accounts, rows: rows)

  it "creates new accounts in owned books, inferring the kind" do
    result = assign({ plaid_account: "fake-checking", choice: "new", book: business.id.to_s, name: "Operating" },
                    { plaid_account: "fake-card", choice: "new", book: business.id.to_s, name: "" },
                    { plaid_account: "fake-savings", choice: "new", book: personal.id.to_s, name: "Rainy day" })
    expect(result).to be_ok
    operating = business.accounts.find_by!(name: "Operating")
    expect(operating).to have_attributes(source: "plaid", kind: "checking", plaid_item: item, plaid_account_id: "fake-checking",
                                         plaid_mask: "0000", plaid_name: "Plaid Checking", plaid_sync_from: nil)
    expect(business.accounts.find_by!(name: "Plaid Credit Card").kind).to eq("credit")
    expect(personal.accounts.find_by!(name: "Rainy day").kind).to eq("savings")
  end

  it "attaches an existing CSV account, defaulting sync-from to its latest transaction" do
    csv = create(:account, :csv, business: personal, name: "Joint Checking")
    create(:transaction, account: csv, posted_on: Date.new(2026, 9, 30), external_id: "h1")
    create(:transaction, account: csv, posted_on: Date.new(2026, 9, 12), external_id: "h2")
    expect(assign({ plaid_account: "fake-checking", choice: "attach", target: csv.id.to_s, sync_from: "" })).to be_ok
    expect(csv.reload).to have_attributes(source: "plaid", plaid_account_id: "fake-checking", plaid_sync_from: Date.new(2026, 9, 30))
  end

  it "uses an entered sync-from date and rejects a bad one" do
    csv = create(:account, :csv, business: business)
    expect(assign({ plaid_account: "fake-checking", choice: "attach", target: csv.id.to_s, sync_from: "2000-01-01" })).to be_ok
    expect(csv.reload.plaid_sync_from).to eq(Date.new(2000, 1, 1))
    other = create(:account, :csv, business: business)
    result = assign({ plaid_account: "fake-card", choice: "attach", target: other.id.to_s, sync_from: "13/45/2026" })
    expect(result.errors).to eq("fake-card" => "Sync from is not a valid date")
    expect(other.reload.source).to eq("csv")
  end

  it "skips accounts and ignores rows for accounts already assigned" do
    create(:account, :plaid, business: business, plaid_item: item, plaid_account_id: "fake-checking")
    expect(assign({ plaid_account: "fake-checking", choice: "new", book: business.id.to_s },
                  { plaid_account: "fake-card", choice: "skip" })).to be_ok
    expect(Account.where(plaid_account_id: "fake-checking").count).to eq(1)
    expect(Account.where(plaid_account_id: "fake-card")).to be_empty
  end

  it "rejects books and accounts the user doesn't own, and applies nothing when any row fails" do
    edited = create(:business)
    create(:membership, user: user, business: edited, role: "editor")
    theirs = create(:account, :csv, business: edited)
    linked = create(:account, :plaid, business: business)
    archived = create(:account, :csv, business: business, archived_at: Time.current)
    result = assign({ plaid_account: "fake-checking", choice: "new", book: business.id.to_s },
                    { plaid_account: "fake-savings", choice: "new", book: edited.id.to_s },
                    { plaid_account: "fake-card", choice: "attach", target: theirs.id.to_s })
    expect(result.errors).to eq("fake-savings" => "Choose a book you own",
                                "fake-card" => "Choose an existing manual or CSV account in a book you own")
    expect(Account.where(plaid_account_id: "fake-checking")).to be_empty
    [ linked, archived ].each do |target|
      expect(assign({ plaid_account: "fake-card", choice: "attach", target: target.id.to_s })).not_to be_ok
    end
  end

  it "rejects unknown Plaid accounts and choices" do
    expect(assign({ plaid_account: "not-in-this-item", choice: "new", book: business.id.to_s }).errors)
      .to eq("not-in-this-item" => "That account isn't part of this connection")
    expect(assign({ plaid_account: "fake-card", choice: "merge" }).errors).to eq("fake-card" => "Choose skip, new account, or existing account")
  end

  it "maps Plaid types to account kinds" do
    expect(described_class.kind_for("depository", "checking")).to eq("checking")
    expect(described_class.kind_for("depository", "savings")).to eq("savings")
    expect(described_class.kind_for("depository", "cd")).to eq("other")
    expect(described_class.kind_for("credit", "credit card")).to eq("credit")
    expect(described_class.kind_for("loan", "mortgage")).to eq("other")
  end
end
```

`spec/requests/plaid_assignments_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Plaid account assignment" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:owner) { user_with_role("owner", business) }
  let!(:item) { create(:plaid_item, created_by: owner) }
  let!(:csv) { create(:account, :csv, business: business, name: "Business Checking") }

  before { sign_in_as owner }

  it "lists the bank's accounts with the choices" do
    get plaid_item_assignment_path(item)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Plaid Checking", "····0000", "Plaid Credit Card", "Pat Consulting", "Business Checking")
  end

  it "applies the assignment and starts a sync" do
    params = { assignments: [
      { plaid_account: "fake-checking", choice: "attach", book: business.id, target: csv.id, name: "", sync_from: "" },
      { plaid_account: "fake-card", choice: "new", book: business.id, target: "", name: "Business Card", sync_from: "" },
      { plaid_account: "fake-savings", choice: "skip", book: business.id, target: "", name: "", sync_from: "" }
    ] }
    expect { patch plaid_item_assignment_path(item), params: params }.to have_enqueued_job(PlaidSyncJob).with(item)
    expect(response).to redirect_to(plaid_item_path(item))
    expect(csv.reload.plaid_account_id).to eq("fake-checking")
    expect(business.accounts.find_by!(name: "Business Card")).to be_plaid
  end

  it "re-renders with the row's error and keeps what was entered" do
    params = { assignments: [ { plaid_account: "fake-card", choice: "new", book: create(:business).id, target: "", name: "Typed name", sync_from: "" } ] }
    patch plaid_item_assignment_path(item), params: params
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Choose a book you own", "Typed name")
    expect(Account.where(plaid_account_id: "fake-card")).to be_empty
  end

  it "shows assigned accounts read-only" do
    create(:account, :plaid, business: business, plaid_item: item, plaid_account_id: "fake-checking", name: "Operating")
    get plaid_item_assignment_path(item)
    expect(response.body).to include("Assigned to Pat Consulting › Operating")
  end

  it "404s for users who can't manage the item" do
    sign_in_as user_with_role("owner", create(:business))
    get plaid_item_assignment_path(item)
    expect(response).to have_http_status(:not_found)
  end
end
```

In `spec/requests/plaid_items_spec.rb`, change the create example's last line to `expect(response).to redirect_to(plaid_item_assignment_path(item))`.

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/services/plaid_feed/assignment_spec.rb spec/requests/plaid_assignments_spec.rb spec/requests/plaid_items_spec.rb`
Expected: FAIL (`uninitialized constant PlaidFeed::Assignment`, missing route).

- [ ] **Step 3: Implement the service**

`app/services/plaid_feed/assignment.rb`:

```ruby
module PlaidFeed
  # Applies the assignment page: each Plaid account is skipped, becomes a new account in a book the user owns,
  # or feeds an existing manual/CSV account there. All rows apply together or not at all.
  class Assignment
    Result = Data.define(:errors) do
      def ok? = errors.empty?
    end

    def self.call(item:, user:, plaid_accounts:, rows:) = new(item, user).call(plaid_accounts, rows)

    def self.kind_for(type, subtype)
      return "credit" if type == "credit"
      return "other" unless type == "depository"

      %w[checking savings].include?(subtype) ? subtype : "other"
    end

    def initialize(item, user)
      @item = item
      @books = user.owned_books
    end

    def call(plaid_accounts, rows)
      by_id = plaid_accounts.index_by { _1[:account_id] }
      assigned = @item.accounts.pluck(:plaid_account_id).to_set
      @errors = {}
      ApplicationRecord.transaction do
        rows.each do |row|
          key = row[:plaid_account].to_s
          plaid = by_id[key]
          next @errors[key] = "That account isn't part of this connection" unless plaid
          next if assigned.include?(key)

          apply(plaid, row)
        end
        raise ActiveRecord::Rollback if @errors.any?
      end
      Result.new(errors: @errors)
    end

    private

    def apply(plaid, row)
      case row[:choice].to_s
      when "", "skip" then nil
      when "new" then create_account(plaid, row)
      when "attach" then attach_account(plaid, row)
      else @errors[plaid[:account_id]] = "Choose skip, new account, or existing account"
      end
    end

    def create_account(plaid, row)
      book = @books.find_by(id: row[:book])
      return @errors[plaid[:account_id]] = "Choose a book you own" unless book

      sync_from = parse_date(plaid, row[:sync_from])
      return if @errors.key?(plaid[:account_id])

      account = book.accounts.new(name: row[:name].presence || plaid[:name], source: "plaid",
                                  kind: self.class.kind_for(plaid[:type], plaid[:subtype]), plaid_sync_from: sync_from, **link(plaid))
      @errors[plaid[:account_id]] = account.errors.full_messages.to_sentence unless account.save
    end

    def attach_account(plaid, row)
      account = Account.where(business: @books).active.where(plaid_account_id: nil, source: %w[manual csv]).find_by(id: row[:target])
      return @errors[plaid[:account_id]] = "Choose an existing manual or CSV account in a book you own" unless account

      sync_from = row[:sync_from].present? ? parse_date(plaid, row[:sync_from]) : account.transactions.maximum(:posted_on)
      return if @errors.key?(plaid[:account_id])

      @errors[plaid[:account_id]] = account.errors.full_messages.to_sentence unless
        account.update(source: "plaid", plaid_sync_from: sync_from, **link(plaid))
    end

    def link(plaid) = { plaid_item: @item, plaid_account_id: plaid[:account_id], plaid_mask: plaid[:mask], plaid_name: plaid[:name] }

    def parse_date(plaid, value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      @errors[plaid[:account_id]] = "Sync from is not a valid date"
      nil
    end
  end
end
```

- [ ] **Step 4: Route, controller, view**

`config/routes.rb`: inside `resources :plaid_items ... do` add

```ruby
    resource :assignment, only: %i[show update], controller: "plaid_assignments"
```

`app/controllers/plaid_assignments_controller.rb`:

```ruby
class PlaidAssignmentsController < ApplicationController
  include PlaidScoped

  ROW_KEYS = %i[plaid_account choice book target name sync_from].freeze

  before_action :set_item
  helper_method :row_value

  def show
    load_choices(gateway.accounts(@item.access_token))
  rescue PlaidGateway::Error => e
    @gateway_error = e.message
  end

  def update
    plaid_accounts = gateway.accounts(@item.access_token)
    rows = params[:assignments].present? ? params.expect(assignments: [ ROW_KEYS ]) : []
    result = PlaidFeed::Assignment.call(item: @item, user: Current.user, plaid_accounts: plaid_accounts, rows: rows)
    if result.ok?
      PlaidSyncJob.perform_later(@item)
      redirect_to plaid_item_path(@item), notice: "Accounts saved. Syncing now."
    else
      @errors = result.errors
      @submitted = rows.index_by { _1[:plaid_account].to_s }
      load_choices(plaid_accounts)
      render :show, status: :unprocessable_content
    end
  rescue PlaidGateway::Error => e
    redirect_to plaid_item_path(@item), alert: "Plaid: #{e.message}"
  end

  private

  def load_choices(plaid_accounts)
    @plaid_accounts = plaid_accounts
    @assigned = @item.accounts.includes(:business).index_by(&:plaid_account_id)
    @books = Current.user.owned_books.order(:kind, :name)
    @attachable = Account.where(business: @books).active.where(plaid_account_id: nil, source: %w[manual csv])
      .includes(:business).order(:name)
    @errors ||= {}
  end

  def row_value(plaid, key) = (@submitted || {}).fetch(plaid[:account_id], {})[key]
end
```

`app/views/plaid_assignments/show.html.erb`:

```erb
<h1>Assign <%= @item.institution_name %> accounts</h1>
<% if @gateway_error %>
  <p class="errors">Couldn't load accounts from Plaid: <%= @gateway_error %></p>
  <%= link_to "Try again", plaid_item_assignment_path(@item) %>
<% else %>
  <p>Choose where each bank account's transactions go. Skipped accounts can be assigned later.</p>
  <%= form_with url: plaid_item_assignment_path(@item), method: :patch do |f| %>
    <table>
      <thead><tr><th>Bank account</th><th>Do</th><th>New account in</th><th>Name</th><th>Existing account</th><th>Sync from</th></tr></thead>
      <tbody>
        <% @plaid_accounts.each do |plaid| %>
          <% assigned = @assigned[plaid[:account_id]] %>
          <tr id="plaid_account_<%= plaid[:account_id].parameterize %>">
            <td><%= plaid[:name] %> ····<%= plaid[:mask] %> (<%= plaid[:subtype].presence || plaid[:type] %>)</td>
            <% if assigned %>
              <td colspan="5">Assigned to <%= book_label(assigned.business) %> › <%= assigned.name %></td>
            <% else %>
              <td>
                <%= hidden_field_tag "assignments[][plaid_account]", plaid[:account_id], id: nil %>
                <%= select_tag "assignments[][choice]",
                      options_for_select([ [ "Skip", "skip" ], [ "New account", "new" ], [ "Existing account", "attach" ] ], row_value(plaid, :choice)),
                      id: nil, aria: { label: "What to do with #{plaid[:name]}" } %>
                <% if (error = @errors[plaid[:account_id]]) %>
                  <p class="errors"><%= error %></p>
                <% end %>
              </td>
              <td>
                <%= select_tag "assignments[][book]", options_for_select(@books.map { [ book_label(_1), _1.id.to_s ] }, row_value(plaid, :book)),
                      id: nil, aria: { label: "Book for #{plaid[:name]}" } %>
              </td>
              <td>
                <%= text_field_tag "assignments[][name]", row_value(plaid, :name) || plaid[:name], id: nil,
                      aria: { label: "Name for #{plaid[:name]}" } %>
              </td>
              <td>
                <%= select_tag "assignments[][target]",
                      grouped_options_for_select(@attachable.group_by { book_label(_1.business) }.transform_values { |accounts| accounts.map { [ _1.name, _1.id.to_s ] } },
                                                 row_value(plaid, :target)),
                      include_blank: "—", id: nil, aria: { label: "Existing account for #{plaid[:name]}" } %>
              </td>
              <td>
                <%= date_field_tag "assignments[][sync_from]", row_value(plaid, :sync_from), id: nil, aria: { label: "Sync from for #{plaid[:name]}" } %>
              </td>
            <% end %>
          </tr>
        <% end %>
      </tbody>
    </table>
    <p>For an existing account, a blank "Sync from" starts after its latest transaction; enter an early date to import everything Plaid has. For a new account, blank imports everything.</p>
    <%= f.submit "Save assignments" %>
  <% end %>
<% end %>
```

`app/controllers/plaid_items_controller.rb` `create`: redirect to `plaid_item_assignment_path(item)` instead of `plaid_item_path(item)`.

`app/views/plaid_items/show.html.erb`: before the `Sync now` button add

```erb
<% unassigned = @plaid_accounts.to_a.count { !@item.accounts.map(&:plaid_account_id).include?(_1[:account_id]) } %>
<p>
  <%= link_to "Assign accounts", plaid_item_assignment_path(@item) %>
  <%= " · #{pluralize(unassigned, "bank account")} not assigned" if unassigned.positive? %>
</p>
```

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/services/plaid_feed/assignment_spec.rb spec/requests/plaid_assignments_spec.rb spec/requests/plaid_items_spec.rb` → PASS. Then `bundle exec rspec`, `bin/rubocop`, `bin/brakeman --no-pager` (no new warnings: no `*_id` keys are permitted).

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app spec
git commit -m "Plaid: assign accounts to owned books (new, attach with cutoff, skip)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Reconnect in update mode; status on the dashboard and accounts list

**Files:**
- Create: `app/controllers/plaid_reconnections_controller.rb`, `app/views/plaid_reconnections/new.html.erb`, `app/views/plaid_items/_reconnect_banners.html.erb`, `app/views/accounts/_plaid_status.html.erb`, `spec/requests/plaid_reconnections_spec.rb`
- Modify: `config/routes.rb`, `app/models/plaid_item.rb`, `app/views/plaid_items/show.html.erb`, `app/controllers/dashboards_controller.rb`, `app/views/dashboards/show.html.erb`, `app/controllers/accounts_controller.rb` (`index` includes), `app/views/accounts/index.html.erb`

**Interfaces:**
- Consumes: `PlaidScoped`, `plaid_items/_link` partial (Task 11), gateway `create_link_token(user:, access_token:)` (Tasks 5–6).
- Produces: routes `new_plaid_item_reconnection_path(item)`, `plaid_item_reconnection_path(item)` (POST); `PlaidItem.needing_reconnect_for(user)` (login_required items that feed a book the user can see, or that the user manages; `none` when Plaid is disabled).

- [ ] **Step 1: Write the failing spec**

`spec/requests/plaid_reconnections_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Reconnecting a bank" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:owner) { user_with_role("owner", business) }
  let!(:item) { create(:plaid_item, created_by: owner, status: "login_required", last_error: "ITEM_LOGIN_REQUIRED: log in") }
  let!(:account) { create(:account, :plaid, business: business, plaid_item: item, plaid_mask: "0000", name: "Operating") }

  it "opens Link in update mode and marks the item connected afterwards" do
    sign_in_as owner
    get new_plaid_item_reconnection_path(item)
    expect(response.body).to include("link-fake-#{owner.id}-update")
    expect { post plaid_item_reconnection_path(item), params: { public_token: "public-x" } }.to have_enqueued_job(PlaidSyncJob).with(item)
    expect(item.reload).to have_attributes(status: "ok", last_error: nil)
    expect(response).to redirect_to(plaid_item_path(item))
  end

  it "404s for users who can't manage the item" do
    sign_in_as user_with_role("owner", create(:business))
    get new_plaid_item_reconnection_path(item)
    expect(response).to have_http_status(:not_found)
    post plaid_item_reconnection_path(item)
    expect(response).to have_http_status(:not_found)
  end

  it "shows a reconnect banner on the dashboard: a button for managers, text for other members" do
    sign_in_as owner
    get root_path
    expect(response.body).to include("Your connection to Demo Bank needs to be renewed.", new_plaid_item_reconnection_path(item))

    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(response.body).to include("Your connection to Demo Bank needs to be renewed.")
    expect(response.body).not_to include(new_plaid_item_reconnection_path(item))

    sign_in_as user_with_role("owner", create(:business))
    get root_path
    expect(response.body).not_to include("needs to be renewed")

    item.update!(status: "ok")
    sign_in_as owner
    get root_path
    expect(response.body).not_to include("needs to be renewed")
  end

  it "shows Plaid status on the accounts list and a Reconnect link on the item page" do
    sign_in_as user_with_role("viewer", business)
    get business_accounts_path(business)
    expect(response.body).to include("Demo Bank ····0000", "not synced yet", "needs reconnecting")

    sign_in_as owner
    get plaid_item_path(item)
    expect(response.body).to include(new_plaid_item_reconnection_path(item))
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/requests/plaid_reconnections_spec.rb`
Expected: FAIL (missing route `new_plaid_item_reconnection_path`).

- [ ] **Step 3: Implement**

`config/routes.rb`: inside `resources :plaid_items ... do` add

```ruby
    resource :reconnection, only: %i[new create], controller: "plaid_reconnections"
```

`app/models/plaid_item.rb`: add below `sync_all_later`:

```ruby
  # Items that need the user to log in again, for the dashboard banner.
  def self.needing_reconnect_for(user)
    return none unless PlaidGateway.enabled?

    visible = Account.where(business: user.accessible_businesses).select(:plaid_item_id)
    login_required.where(id: visible).or(login_required.manageable_by(user))
  end
```

`app/controllers/plaid_reconnections_controller.rb`:

```ruby
class PlaidReconnectionsController < ApplicationController
  include PlaidScoped

  before_action :set_item

  def new
    @link_token = gateway.create_link_token(user: Current.user, access_token: @item.access_token)
  rescue PlaidGateway::Error => e
    redirect_to plaid_item_path(@item), alert: "Plaid: #{e.message}"
  end

  # Link's update mode needs no token exchange: the existing access token works again once the user has logged in.
  def create
    @item.update!(status: "ok", last_error: nil)
    PlaidSyncJob.perform_later(@item)
    redirect_to plaid_item_path(@item), notice: "Reconnected #{@item.institution_name}. Syncing now."
  end
end
```

`app/views/plaid_reconnections/new.html.erb`:

```erb
<h1>Reconnect <%= @item.institution_name %></h1>
<p>Your bank needs you to sign in again before goodbooks can keep syncing.</p>
<%= render "plaid_items/link", token: @link_token, url: plaid_item_reconnection_path(@item), label: "Reconnect with Plaid" %>
```

`app/views/plaid_items/_reconnect_banners.html.erb`:

```erb
<% items.each do |item| %>
  <p class="flash flash-alert" id="<%= dom_id(item, :reconnect) %>">
    Your connection to <%= item.institution_name %> needs to be renewed.
    <%= link_to "Reconnect", new_plaid_item_reconnection_path(item) if item.manageable_by?(Current.user) %>
  </p>
<% end %>
```

`app/views/plaid_items/show.html.erb`: after the status paragraph add

```erb
<% if @item.login_required? || @item.error? %>
  <p><%= link_to "Reconnect", new_plaid_item_reconnection_path(@item) %></p>
<% end %>
```

`app/controllers/dashboards_controller.rb` `show`: add as the last line

```ruby
    @reconnect_items = PlaidItem.needing_reconnect_for(Current.user).to_a
```

`app/views/dashboards/show.html.erb`: add as the first line

```erb
<%= render "plaid_items/reconnect_banners", items: @reconnect_items %>
```

`app/views/accounts/_plaid_status.html.erb`:

```erb
<% item = account.plaid_item %>
plaid · <%= item.institution_name %> ····<%= account.plaid_mask %>
· <%= item.last_synced_at ? "synced #{time_ago_in_words(item.last_synced_at)} ago" : "not synced yet" %>
<%= "· needs reconnecting" if item.login_required? %>
```

`app/views/accounts/index.html.erb`: replace `<td><%= account.source %></td>` with

```erb
        <td><%= account.plaid_item ? render("accounts/plaid_status", account: account) : account.source %></td>
```

`app/controllers/accounts_controller.rb` `index`: `@accounts = @business.accounts.includes(:plaid_item).order(:archived_at, :name)`.

- [ ] **Step 4: Run the specs**

Run: `bundle exec rspec spec/requests/plaid_reconnections_spec.rb spec/requests/accounts_spec.rb spec/requests/plaid_items_spec.rb` → PASS. Then `bundle exec rspec`, `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app spec/requests/plaid_reconnections_spec.rb
git commit -m "Plaid: reconnect in update mode, dashboard banner, account status

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Verified webhooks

**Files:**
- Create: `app/controllers/plaid_webhooks_controller.rb`, `spec/requests/plaid_webhooks_spec.rb`
- Modify: `config/routes.rb`

**Interfaces:**
- Consumes: `PlaidFeed::WebhookVerifier` (Task 7), `PlaidGateway.current.webhook_verification_key` (Tasks 5–6), `FakePlaidGateway#sign_webhook` / `#expire_key!` (Task 6), `PlaidSyncJob` (Task 9).
- Produces: `POST /plaid/webhooks` (`plaid_webhooks_path`); 401 unverified, 400 unparseable, 404 when Plaid is disabled, 429 when rate limited, else 200.

- [ ] **Step 1: Write the failing spec**

`spec/requests/plaid_webhooks_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Plaid webhooks" do
  let!(:item) { create(:plaid_item, item_id: "item-1") }

  def deliver(payload, token: :sign, raw: nil)
    body = raw || payload.to_json
    token = plaid_gateway.sign_webhook(body) if token == :sign
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Plaid-Verification"] = token if token
    post plaid_webhooks_path, params: body, headers: headers
  end

  def sync_available(item_id = "item-1") = { webhook_type: "TRANSACTIONS", webhook_code: "SYNC_UPDATES_AVAILABLE", item_id: item_id }

  it "starts a sync when Plaid says updates are available, without a login" do
    expect { deliver(sync_available) }.to have_enqueued_job(PlaidSyncJob).with(item)
    expect(response).to have_http_status(:ok)
  end

  it "marks the item login_required on a login error or a pending expiration" do
    deliver(webhook_type: "ITEM", webhook_code: "ERROR", item_id: "item-1",
            error: { error_code: "ITEM_LOGIN_REQUIRED", error_message: "the login details have changed" })
    expect(item.reload).to have_attributes(status: "login_required", last_error: "ITEM_LOGIN_REQUIRED: the login details have changed")
    item.update!(status: "ok")
    deliver(webhook_type: "ITEM", webhook_code: "PENDING_EXPIRATION", item_id: "item-1")
    expect(item.reload).to be_login_required
  end

  it "marks the item ok and syncs when the login is repaired" do
    item.update!(status: "login_required", last_error: "x")
    expect { deliver(webhook_type: "ITEM", webhook_code: "LOGIN_REPAIRED", item_id: "item-1") }.to have_enqueued_job(PlaidSyncJob)
    expect(item.reload).to have_attributes(status: "ok", last_error: nil)
  end

  it "acknowledges unknown items and webhook types without doing anything" do
    expect { deliver(sync_available("item-unknown")) }.not_to have_enqueued_job
    expect(response).to have_http_status(:ok)
    expect { deliver(webhook_type: "TRANSACTIONS", webhook_code: "RECURRING_TRANSACTIONS_UPDATE", item_id: "item-1") }.not_to have_enqueued_job
    expect(response).to have_http_status(:ok)
  end

  it "rejects unverified requests with 401" do
    other_key = OpenSSL::PKey::EC.generate("prime256v1")
    body = sync_available.to_json
    [
      nil,
      "garbage",
      plaid_gateway.sign_webhook(body, key: other_key),
      plaid_gateway.sign_webhook(body, iat: 6.minutes.ago.to_i),
      plaid_gateway.sign_webhook(sync_available("item-2").to_json)
    ].each do |token|
      expect { deliver(nil, token: token, raw: body) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unauthorized)
    end
    plaid_gateway.expire_key!
    deliver(sync_available)
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 400 for a verified body that isn't JSON" do
    deliver(nil, raw: "not json")
    expect(response).to have_http_status(:bad_request)
  end

  it "404s when Plaid is disabled" do
    PlaidGateway.current = nil
    post plaid_webhooks_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:not_found)
  end

  context "with rate limiting" do
    include_context "with rate limiting"

    it "allows 60 requests a minute" do
      60.times { deliver(nil, token: "garbage", raw: "{}") }
      expect(response).to have_http_status(:unauthorized)
      deliver(nil, token: "garbage", raw: "{}")
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/requests/plaid_webhooks_spec.rb`
Expected: FAIL (missing route `plaid_webhooks_path`).

- [ ] **Step 3: Implement**

`config/routes.rb`: below the `resources :plaid_items` block add

```ruby
  post "plaid/webhooks", to: "plaid_webhooks#create", as: :plaid_webhooks
```

`app/controllers/plaid_webhooks_controller.rb`:

```ruby
# Plaid calls this without a session; the signed Plaid-Verification header is the only authentication.
class PlaidWebhooksController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_household
  skip_forgery_protection
  rate_limit to: 60, within: 1.minute, with: -> { head :too_many_requests }

  before_action :require_plaid!

  def create
    body = request.raw_post
    verifier.verify!(body: body, token: request.headers["Plaid-Verification"])
    handle(JSON.parse(body))
    head :ok
  rescue PlaidFeed::WebhookVerifier::Invalid => e
    Rails.logger.info("Plaid webhook rejected: #{e.message}")
    head :unauthorized
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def require_plaid!
    head :not_found unless PlaidGateway.enabled?
  end

  def verifier
    PlaidFeed::WebhookVerifier.new(key_fetcher: lambda { |kid|
      Rails.cache.fetch("plaid/webhook_key/#{kid}", expires_in: 24.hours) { PlaidGateway.current.webhook_verification_key(kid) }
    })
  end

  def handle(payload)
    item = PlaidItem.find_by(item_id: payload["item_id"].to_s)
    return unless item

    case [ payload["webhook_type"], payload["webhook_code"] ]
    in [ "TRANSACTIONS", "SYNC_UPDATES_AVAILABLE" ]
      PlaidSyncJob.perform_later(item)
    in [ "ITEM", "ERROR" ] if payload.dig("error", "error_code") == "ITEM_LOGIN_REQUIRED"
      item.update!(status: "login_required", last_error: "ITEM_LOGIN_REQUIRED: #{payload.dig("error", "error_message")}")
    in [ "ITEM", "PENDING_EXPIRATION" | "PENDING_DISCONNECT" ]
      item.update!(status: "login_required")
    in [ "ITEM", "LOGIN_REPAIRED" ]
      item.update!(status: "ok", last_error: nil)
      PlaidSyncJob.perform_later(item)
    else
      nil
    end
  end
end
```

- [ ] **Step 4: Run the specs**

Run: `bundle exec rspec spec/requests/plaid_webhooks_spec.rb` → PASS. Then `bundle exec rspec`, `bin/rubocop`, `bin/brakeman --no-pager` (`skip_forgery_protection` on a token-verified API endpoint is expected; if Brakeman flags it, add it to `config/brakeman.ignore` with the note "Plaid webhook: authenticated by the signed Plaid-Verification JWT, not a session").

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/plaid_webhooks_controller.rb spec/requests/plaid_webhooks_spec.rb
git commit -m "Plaid: verified webhooks trigger syncs and track login status

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Needs review in the inbox, transaction filter, and dashboard

**Files:**
- Create: `app/controllers/transaction_reviews_controller.rb`, `app/views/inboxes/_review_rows.html.erb`, `spec/requests/transaction_reviews_spec.rb`
- Modify: `config/routes.rb`, `app/controllers/inboxes_controller.rb`, `app/views/inboxes/show.html.erb`, `app/controllers/household_inboxes_controller.rb`, `app/views/household_inboxes/show.html.erb`, `app/models/transaction_filter.rb`, `app/views/transactions/index.html.erb`, `app/controllers/dashboards_controller.rb`, `app/views/dashboards/show.html.erb`

**Interfaces:**
- Consumes: `Transaction.needs_review`, `#review_message` (Task 1), `book_label` (Task 11).
- Produces: route `business_transaction_review_path(business, txn)` (PATCH, param `decision` = `keep`|`exclude`); Turbo target `dom_id(txn, :review)` (`review_transaction_<id>`); `TransactionFilter` status `"review"`.

- [ ] **Step 1: Write the failing spec**

`spec/requests/transaction_reviews_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Transactions needing review" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:account) { create(:account, :plaid, business: business, name: "Operating") }
  let!(:category) { create(:category, business: business, name: "Office expense") }
  let!(:flagged) do
    create(:transaction, account: account, payee: "USPS", plaid_transaction_id: "p-1", category: category, categorized_by: "user",
                         review_reason: "removed_by_bank")
  end

  it "lists flagged rows above the inbox, with the reason, in the business and household inboxes" do
    sign_in_as user_with_role("viewer", business)
    get business_inbox_path(business)
    expect(response.body).to include("Needs review (1)", "USPS", "Removed by the bank", "Office expense")
    expect(response.body).not_to include(business_transaction_review_path(business, flagged))
    get household_inbox_path
    expect(response.body).to include("Needs review (1)", "Removed by the bank")
  end

  it "keeps a row with a turbo stream that removes it from the list" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_review_path(business, flagged), params: { decision: "keep" }, as: :turbo_stream
    expect(response.body).to include(%(action="remove" target="review_transaction_#{flagged.id}"))
    expect(flagged.reload).to have_attributes(review_reason: nil, excluded: false)
  end

  it "excludes a row (HTML fallback redirects back)" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_review_path(business, flagged), params: { decision: "exclude" }
    expect(response).to redirect_to(business_inbox_path(business))
    expect(flagged.reload).to have_attributes(review_reason: nil, excluded: true)
  end

  it "won't exclude a deposit linked to an invoice" do
    income = create(:category, :income, business: business)
    flagged.update!(amount_cents: 120_000, category: income)
    InvoicePayments.link(invoice: create(:invoice, business: business, amount_cents: 120_000, number: "INV-1042"), deposit: flagged)
    sign_in_as user_with_role("editor", business)
    patch business_transaction_review_path(business, flagged), params: { decision: "exclude" }
    expect(flash[:alert]).to include("Linked to INV-1042")
    expect(flagged.reload).to have_attributes(review_reason: "removed_by_bank", excluded: false)
  end

  it "enforces access and input" do
    sign_in_as user_with_role("viewer", business)
    patch business_transaction_review_path(business, flagged), params: { decision: "keep" }
    expect(response).to have_http_status(:forbidden)

    sign_in_as user_with_role("editor", business)
    patch business_transaction_review_path(business, flagged), params: { decision: "delete" }
    expect(response).to have_http_status(:unprocessable_content)
    unflagged = create(:transaction, account: account)
    patch business_transaction_review_path(business, unflagged), params: { decision: "keep" }
    expect(response).to have_http_status(:not_found)

    sign_in_as user_with_role("editor", create(:business))
    patch business_transaction_review_path(business, flagged), params: { decision: "keep" }
    expect(response).to have_http_status(:not_found)
  end

  it "filters the transaction list to rows needing review" do
    create(:transaction, account: account, payee: "UNFLAGGED")
    sign_in_as user_with_role("viewer", business)
    get business_transactions_path(business, status: "review")
    expect(response.body).to include("USPS", "Needs review")
    expect(response.body).not_to include("UNFLAGGED")
  end

  it "counts rows needing review per book on the dashboard" do
    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(response.body).to include("Needs review", "Pat Consulting: 1 transaction")
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/requests/transaction_reviews_spec.rb`
Expected: FAIL (missing route `business_transaction_review_path`).

- [ ] **Step 3: Implement**

`config/routes.rb`: inside `resources :transactions, except: :show do` add

```ruby
      resource :review, only: :update, controller: "transaction_reviews"
```

`app/controllers/transaction_reviews_controller.rb`:

```ruby
# Resolves a row Plaid removed or changed after the user had worked on it: keep it as is, or exclude it.
class TransactionReviewsController < ApplicationController
  include BusinessScoped

  DECISIONS = {
    "keep" => { review_reason: nil },
    "exclude" => { review_reason: nil, excluded: true }
  }.freeze

  before_action :require_editor!

  def update
    txn = Transaction.for_businesses(@business.id).needs_review.find(params[:transaction_id])
    attrs = DECISIONS[params[:decision]]
    return head :unprocessable_content unless attrs

    unless txn.update(attrs)
      return redirect_back_or_to business_inbox_path(@business), alert: txn.errors.full_messages.to_sentence
    end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(helpers.dom_id(txn, :review)) }
      format.html { redirect_back_or_to business_inbox_path(@business) }
    end
  end
end
```

`app/views/inboxes/_review_rows.html.erb`:

```erb
<% if rows.any? %>
  <h2>Needs review (<%= rows.size %>)</h2>
  <table>
    <thead><tr><th>Date</th><th>Account</th><th>Payee</th><th class="num">Amount</th><th>Category</th><th>Why</th><th></th></tr></thead>
    <tbody>
      <% rows.each do |txn| %>
        <tr id="<%= dom_id(txn, :review) %>">
          <td><%= txn.posted_on %></td>
          <td><%= txn.account.name %></td>
          <td><%= txn.payee %></td>
          <td class="num"><%= money(txn.amount_cents) %></td>
          <td><%= txn.transfer? ? "Transfer" : txn.category&.name || "Uncategorized" %></td>
          <td><%= txn.review_message %></td>
          <td>
            <% if editable %>
              <%= button_to "Keep", business_transaction_review_path(business, txn), method: :patch, params: { decision: "keep" }, form_class: "inline-form" %>
              <%= button_to "Exclude", business_transaction_review_path(business, txn), method: :patch, params: { decision: "exclude" }, form_class: "inline-form" %>
            <% end %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>
```

`app/controllers/inboxes_controller.rb` `show`: add

```ruby
    @review = Transaction.for_businesses(@business.id).needs_review.includes(:account, :category).order(posted_on: :desc, id: :desc).to_a
```

`app/views/inboxes/show.html.erb`: after the `Apply rules to inbox` block (`<% end %>`), add

```erb
<%= render "inboxes/review_rows", business: @business, rows: @review, editable: current_membership.can_edit? %>
```

`app/controllers/household_inboxes_controller.rb` `show`: add

```ruby
    @reviews = Transaction.for_businesses(businesses.map(&:id)).needs_review.includes(:account, :category)
      .order(posted_on: :desc, id: :desc).group_by { _1.account.business_id }
```

`app/views/household_inboxes/show.html.erb`: right after each group's `<h2>…</h2>` line add

```erb
  <%= render "inboxes/review_rows", business: business, rows: @reviews.fetch(business.id, []), editable: @memberships.fetch(business.id).can_edit? %>
```

`app/models/transaction_filter.rb` `filtered`: after `relation = relation.inbox if @params[:status] == "inbox"` add

```ruby
    relation = relation.needs_review if @params[:status] == "review"
```

`app/views/transactions/index.html.erb`: the status select becomes `[["All", ""], ["Inbox only", "inbox"], ["Needs review", "review"]]`.

`app/controllers/dashboards_controller.rb` `show`: add

```ruby
    @review_counts = Transaction.for_businesses(Current.user.accessible_businesses.select(:id)).needs_review
      .group("accounts.business_id").count
    @review_books = Current.user.accessible_businesses.where(id: @review_counts.keys).order(:name)
```

`app/views/dashboards/show.html.erb`: add at the end

```erb
<% if @review_counts.any? %>
  <h2>Needs review</h2>
  <ul>
    <% @review_books.each do |book| %>
      <li><%= link_to "#{book_label(book)}: #{pluralize(@review_counts[book.id], "transaction")}", business_inbox_path(book) %></li>
    <% end %>
  </ul>
<% end %>
```

- [ ] **Step 4: Run the specs**

Run: `bundle exec rspec spec/requests/transaction_reviews_spec.rb spec/requests/inbox_spec.rb spec/requests/transaction_filters_spec.rb` → PASS. Then `bundle exec rspec`, `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app spec/requests/transaction_reviews_spec.rb
git commit -m "Plaid: needs-review section with keep/exclude, filter, dashboard count

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: Demo data

**Files:**
- Modify: `lib/demo_seeder.rb`, `spec/lib/demo_seeder_spec.rb`

**Interfaces:**
- Consumes: `FakePlaidGateway` with `DEMO_PUBLIC_TOKEN` / `DEMO_ACCOUNTS` (Task 6), `PlaidFeed::Assignment` (Task 12), `PlaidFeed::Sync` (Task 8).

- [ ] **Step 1: Write the failing spec**

Add to `spec/lib/demo_seeder_spec.rb`:

```ruby
  it "connects a fake Demo Bank feeding a business and the personal book without duplicating CSV history" do
    run
    pat = User.find_by!(email_address: "pat@example.com")
    item = PlaidItem.sole
    expect(item).to have_attributes(institution_name: "Demo Bank", status: "ok", created_by: pat)
    expect(item.last_synced_at).to be_present
    expect(item.accounts.map(&:name)).to contain_exactly("Operating (Demo Bank)", "Business Visa (Demo Bank)", "Joint Checking")
    joint = Account.find_by!(name: "Joint Checking")
    expect(joint.transactions.where.not(plaid_transaction_id: nil).where.not(external_id: nil).count).to be >= 5
    expect(joint.transactions.where(external_id: nil)).to be_empty
    expect(Transaction.where.not(plaid_transaction_id: nil).where(categorized_by: "rule")).to exist
    expect(Transaction.needs_review.sole).to have_attributes(payee: "USPS", review_reason: "removed_by_bank")
  end
```

(The existing examples keep passing: claimed rows don't change the tithe ledger, no rules are added, and nothing is dated after `today`.)

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb`
Expected: FAIL (`PlaidItem.sole` finds nothing).

- [ ] **Step 3: Implement**

`lib/demo_seeder.rb`: at the end of `build`, after `seed_personal(household)`, add `seed_plaid(household, pat)`. Add these private methods after `seed_personal`:

```ruby
  # A fake "Demo Bank" connection: a new operating account and card for Pat Consulting, and the personal Joint Checking
  # attached with a two-week overlap that Plaid claims instead of duplicating. One synced row ends up flagged for review.
  def seed_plaid(household, pat)
    gateway = FakePlaidGateway.new
    token = gateway.exchange_public_token(FakePlaidGateway::DEMO_PUBLIC_TOKEN)
    access_token = token[:access_token]
    item = PlaidItem.create!(household: household, created_by: pat, item_id: token[:item_id], access_token: access_token,
                             institution_name: gateway.institution_name(access_token))
    consulting = household.businesses.find_by!(name: "Pat Consulting")
    joint = household.personal_book.accounts.find_by!(name: "Joint Checking")
    overlap_from = joint.transactions.maximum(:posted_on) - 14
    result = PlaidFeed::Assignment.call(item: item, user: pat, plaid_accounts: gateway.accounts(access_token), rows: [
      { plaid_account: "demo-operating", choice: "new", book: consulting.id, name: "Operating (Demo Bank)" },
      { plaid_account: "demo-card", choice: "new", book: consulting.id, name: "Business Visa (Demo Bank)" },
      { plaid_account: "demo-joint", choice: "attach", target: joint.id, sync_from: overlap_from.iso8601 }
    ])
    raise "Demo Plaid assignment failed: #{result.errors}" unless result.ok?

    gateway.add_page(access_token, added: demo_bank_rows + joint_overlap_rows(joint, overlap_from))
    PlaidFeed::Sync.call(item, gateway: gateway)

    removed = Transaction.find_by!(plaid_transaction_id: "demo-op-1-usps")
    removed.update!(category: consulting.categories.find_by!(name: "Office expense"), categorized_by: "user")
    gateway.add_page(access_token, removed: [ { transaction_id: "demo-op-1-usps", account_id: "demo-operating" } ])
    PlaidFeed::Sync.call(item.reload, gateway: gateway)
  end

  # Plaid's sign: positive = money out.
  def demo_bank_rows
    3.downto(1).flat_map do |months_ago|
      day = @today - (months_ago * 30)
      [
        FakePlaidGateway.transaction("demo-op-#{months_ago}-wire", account_id: "demo-operating", amount: -2400.0, date: day,
                                     name: "WIRE FROM NORTHWIND TRADERS"),
        FakePlaidGateway.transaction("demo-op-#{months_ago}-adobe", account_id: "demo-operating", amount: 54.99, date: day + 2,
                                     name: "ADOBE *CREATIVE CLD 800-833-6687", merchant_name: "Adobe"),
        FakePlaidGateway.transaction("demo-op-#{months_ago}-usps", account_id: "demo-operating", amount: 18.4, date: day + 5,
                                     name: "USPS PO 4821", merchant_name: "USPS"),
        FakePlaidGateway.transaction("demo-card-#{months_ago}-aws", account_id: "demo-card", amount: 34.12, date: day + 7,
                                     name: "AWS EMEA", merchant_name: "Amazon Web Services"),
        FakePlaidGateway.transaction("demo-card-#{months_ago}-payment", account_id: "demo-card", amount: -500.0, date: day + 20,
                                     name: "CARD PAYMENT THANK YOU"),
        FakePlaidGateway.transaction("demo-card-#{months_ago}-pending", account_id: "demo-card", amount: 12.0, date: day + 21,
                                     name: "PENDING COFFEE", pending: true)
      ]
    end
  end

  # Plaid's copy of the joint account's last two weeks: same amounts, some a day later, cleaner names.
  def joint_overlap_rows(joint, overlap_from)
    joint.transactions.where(posted_on: overlap_from..).order(:posted_on, :id).map.with_index do |txn, index|
      date = index.odd? && txn.posted_on < @today ? txn.posted_on + 1 : txn.posted_on
      FakePlaidGateway.transaction("demo-joint-#{index}", account_id: "demo-joint", amount: -txn.amount_cents / 100.0, date: date,
                                   name: txn.payee.titleize)
    end
  end
```

In `print_summary`, before the final warning line add:

```ruby
    @out.puts "Demo Bank is a fake Plaid connection; it works without Plaid keys."
```

- [ ] **Step 4: Run the specs**

Run: `bundle exec rspec spec/lib/demo_seeder_spec.rb` → PASS (all examples, including the fourteen weekday tithe examples). Then `bin/rails demo:reset` in development and confirm it prints the logins and the Demo Bank line without errors. Then `bundle exec rspec`, `bin/rubocop`.

- [ ] **Step 5: Commit**

```bash
git add lib/demo_seeder.rb spec/lib/demo_seeder_spec.rb
git commit -m "Demo: fake Demo Bank feeding a business and Joint Checking, one row to review

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 17: End-to-end check, docs, PR

**Files:**
- Create: `spec/system/plaid_connection_spec.rb`
- Modify: `README.md`, `.env.example`, `docker-compose.yml`, `docs/roadmap.md`

- [ ] **Step 1: Write the system spec**

`spec/system/plaid_connection_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Connecting a bank", js: true do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:owner) { user_with_role("owner", business) }
  let!(:csv) { create(:account, :csv, business: business, name: "Business Checking") }
  let!(:csv_row) do
    create(:transaction, account: csv, posted_on: Date.current - 5, amount_cents: -4_500, payee: "SQ *COFFEE 8475", external_id: "h1")
  end
  let!(:software) { create(:category, business: business, name: "Software") }
  let!(:rule) { create(:rule, business: business, value: "adobe", category: software) }

  def choose_in(row, label, option) = within(row) { find("select[aria-label='#{label}']").select(option) }

  it "links, assigns, syncs without duplicating CSV history, and resolves a review" do
    system_sign_in_as owner
    click_on "Banks"
    click_on "Connect a bank"
    click_on "Connect with Plaid"
    expect(page).to have_content("Assign Demo Bank accounts")

    item = PlaidItem.sole
    plaid_gateway.add_page(item.access_token, added: [
      FakePlaidGateway.transaction("p-coffee", account_id: "fake-checking", amount: 45.0, date: Date.current - 4, name: "SQ *COFFEE", merchant_name: "Coffee"),
      FakePlaidGateway.transaction("p-adobe", account_id: "fake-checking", amount: 54.99, date: Date.current - 2, name: "ADOBE"),
      FakePlaidGateway.transaction("p-kroger", account_id: "fake-card", amount: 80.0, date: Date.current - 1, name: "KROGER")
    ])
    choose_in("#plaid_account_fake-checking", "What to do with Plaid Checking", "Existing account")
    choose_in("#plaid_account_fake-checking", "Existing account for Plaid Checking", "Business Checking")
    choose_in("#plaid_account_fake-card", "What to do with Plaid Credit Card", "New account")
    within("#plaid_account_fake-card") { find("input[aria-label='Name for Plaid Credit Card']").fill_in(with: "Visa") }
    click_on "Save assignments"
    expect(page).to have_content("Accounts saved. Syncing now.")

    PlaidSyncJob.perform_now(item.reload)
    expect(csv.transactions.count).to eq(2)
    expect(csv_row.reload.plaid_transaction_id).to eq("p-coffee")
    expect(csv.transactions.find_by!(plaid_transaction_id: "p-adobe").category).to eq(software)

    visit business_inbox_path(business)
    expect(page).to have_content("KROGER")
    expect(page).not_to have_content("ADOBE")

    csv_row.update!(category: software, categorized_by: "user")
    plaid_gateway.add_page(item.access_token, removed: [ { transaction_id: "p-coffee", account_id: "fake-checking" } ])
    PlaidSyncJob.perform_now(item.reload)
    visit business_inbox_path(business)
    expect(page).to have_content("Removed by the bank")
    within("#review_transaction_#{csv_row.id}") { click_on "Keep" }
    expect(page).not_to have_css("#review_transaction_#{csv_row.id}")
    expect(csv_row.reload.review_reason).to be_nil
  end
end
```

(The Capybara server runs in this process, so `plaid_gateway` is the same fake the app uses. `PlaidSyncJob.perform_now` stands in for the queue, which the test adapter doesn't run.)

Run: `bundle exec rspec spec/system/plaid_connection_spec.rb` → PASS.

- [ ] **Step 2: Docs and deployment config**

`README.md`: add a section after "Invite links":

```markdown
### Bank feeds (Plaid)

Set `PLAID_CLIENT_ID`, `PLAID_SECRET`, and `PLAID_ENV` (`sandbox` or `production`) to connect banks through Plaid.
Without all three, production hides every Plaid screen; development uses a fake "Demo Bank" so the screens can be tried
without keys (`bin/rails demo:reset` connects it to Pat Consulting and Joint Checking).

- **Banks** (top nav, for anyone who owns a book) → **Connect a bank** opens Plaid Link. Afterwards each bank account
  becomes a new account in a book you own, feeds an existing manual or CSV account (pick "Existing account"; a blank
  "Sync from" starts after its latest transaction), or is skipped.
- Transactions sync daily at 4am, when Plaid's webhook says there are updates, and on **Sync now**. Pending
  transactions are skipped until they post.
- Plaid and CSV dedupe against each other: a row with the same amount within 3 days is claimed rather than duplicated,
  so CSV upload stays available on Plaid accounts as a fallback.
- If the bank removes or changes a transaction you had categorized or linked to an invoice, it shows under
  **Needs review** in the inbox: **Keep** or **Exclude**.
- Webhooks are received at `https://APP_HOST/plaid/webhooks` and verified with Plaid's signature; they need the app
  reachable from the internet (the tunnel). Without them the daily sync still runs.
- If the bank asks you to sign in again, the dashboard shows **Reconnect**.

To try Plaid's sandbox: create a free account at dashboard.plaid.com, copy the sandbox keys from Developers → Keys,
start the app with `PLAID_CLIENT_ID=… PLAID_SECRET=… PLAID_ENV=sandbox bin/dev`, connect "First Platypus Bank", and
sign in with `user_good` / `pass_good`.
```

`.env.example`: append

```
# Optional: Plaid bank feeds. All three or none.
# PLAID_CLIENT_ID=
# PLAID_SECRET=
# PLAID_ENV=production
```

`docker-compose.yml`: under `app.environment` add

```yaml
      PLAID_CLIENT_ID: ${PLAID_CLIENT_ID:-}
      PLAID_SECRET: ${PLAID_SECRET:-}
      PLAID_ENV: ${PLAID_ENV:-}
```

- [ ] **Step 3: Full verification**

Run each and confirm clean output:
- `bundle exec rspec` → all examples, 0 failures, nothing else printed
- `bin/rubocop`
- `bin/brakeman --no-pager`
- `bin/bundler-audit`
- `bin/importmap audit`

- [ ] **Step 4: Commit, push, open the stacked PR**

```bash
git add spec README.md .env.example docker-compose.yml
git commit -m "Plaid: end-to-end spec, README, and deployment env

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin plaid
gh pr create --base tithing --title "Plaid bank feeds (sub-project 5)" --body-file tmp/plaid-pr-body.md
```

Write `tmp/plaid-pr-body.md` (git-ignored) before running `gh pr create`. The PR body has: Summary (Link + assignment to any owned book including Personal, attach-to-existing with cutoff, two-way CSV ↔ Plaid claiming, sync daily/webhook/manual with retries, needs-review flags, reconnect, verified webhooks, fake gateway; stacked on #7 and built in parallel with sales tax, so whichever merges second rebases), the spec and plan paths, the new env vars, and **Acceptance testing** (below), ending with:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Acceptance testing (put the same steps in the PR body and the GB-5 Kaneo task description):

Setup: `bin/rails demo:reset`, then `bin/dev`. Every demo user's password is `demo password 123`; add the printed TOTP secret to an authenticator app. Plaid keys are not needed.

As **Pat** (`pat@example.com`, household owner):
1. [ ] Top nav has **Banks** → "Demo Bank · Connected", feeding Pat Consulting › Operating (Demo Bank), Pat Consulting › Business Visa (Demo Bank), and Personal › Joint Checking.
2. [ ] Dashboard shows "Needs review — Pat Consulting: 1 transaction". Its inbox lists USPS under **Needs review** with "Removed by the bank"; **Keep** removes the row without a page reload, and the dashboard line disappears.
3. [ ] Pat Consulting → Transactions → filter account "Operating (Demo Bank)": three wires, three Adobe charges categorized Software by the rule, three USPS rows; no "PENDING COFFEE". The Visa account's card payments are transfers.
4. [ ] Personal → Transactions → Joint Checking, last two weeks: every row appears once (no Plaid duplicates of the CSV history). Personal → Tithe shows the same "Behind $…" as before the Plaid work (between $230 and $460).
5. [ ] Personal → Accounts: Joint Checking shows "plaid · Demo Bank ····1177 · synced … ago" and still offers **Import CSV**. Then Pat Consulting → Accounts → Operating (Demo Bank) → **Import CSV**: upload a file with the header `Date,Description,Amount` and one row repeating an Adobe charge from that account one day later with amount `-54.99` and description `ADOBE SYSTEMS`; map Date / Description / Amount (MM/DD/YYYY). The preview says "Already synced from bank (… Adobe · -$54.99)" and **Import** reports 0 new transactions and 1 already synced from the bank.
6. [ ] Banks → Demo Bank → **Sync now** → "Sync started."; the page shows a recent "Last synced".
7. [ ] Banks → **Connect a bank** → **Connect with Plaid** (fake) → the assignment page lists Plaid Checking, Plaid Saving, Plaid Credit Card. Choose "New account" in Jordan Design Studio for Plaid Checking, "Existing account" → Pat Consulting › Cash for the card, skip savings → **Save assignments** → the new item page shows both accounts and "1 bank account not assigned".
8. [ ] On that item, **Remove connection** → confirm → "Connection removed."; Pat Consulting › Cash is a manual account again and keeps its transactions.
9. [ ] Run `bin/rails runner 'PlaidItem.find_by!(institution_name: "Demo Bank").update!(status: "login_required")'` and reload the dashboard: "Your connection to Demo Bank needs to be renewed. Reconnect". **Reconnect** → **Reconnect with Plaid** → "Reconnected Demo Bank. Syncing now." and the banner is gone.

As **Jordan** (`jordan@example.com`, editor of the studio and Personal, viewer of Pat Consulting, owns no book):
10. [ ] No **Banks** in the nav; `/plaid_items` and `/plaid_items/1` → 404.
11. [ ] Repeat step 9's runner command: Jordan's dashboard shows the renewal banner as text, without a Reconnect link.

As **the accountant** (`accountant@example.com`, viewer of both businesses):
12. [ ] No **Banks**; `/plaid_items` → 404. Pat Consulting → Accounts shows the Plaid status line for Operating and Visa. The inbox's Needs review rows (if any) have no Keep/Exclude buttons.

Optional, real Plaid sandbox:
13. [ ] Get sandbox keys (README "Bank feeds"), run `PLAID_CLIENT_ID=… PLAID_SECRET=… PLAID_ENV=sandbox bin/dev`, connect "First Platypus Bank" with `user_good` / `pass_good`, assign Plaid Checking as a new account, then **Sync now**. Transactions appear within a minute or two (sandbox may first answer PRODUCT_NOT_READY; the job retries).

- [ ] **Step 5: Get CI green; update the roadmap and Kaneo**

Watch `gh pr checks --watch`; fix anything red. Then in `docs/roadmap.md` set sub-project 5's Status to "In review (PR #N)" and change its `○` to `◐` in the dependency graph; commit and push. Move GB-5 to In Review with a comment linking the PR, and put the acceptance steps in its description.

---

## Summary

| Task | Delivers |
|---|---|
| 1 | `PlaidItem`, Plaid fields on accounts/transactions, review reasons, `User#owned_books` |
| 2 | Read-only per imported row; CSV upload on Plaid-fed accounts |
| 3 | Pure `PlaidFeed::TransactionMapper` (sign, exact cents, payee, pending) |
| 4 | Pure `PlaidFeed::ClaimMatcher` (same amount, ±3 days, one-to-one) |
| 5 | `PlaidGateway` over the `plaid` gem, error translation, `current`/`enabled?` |
| 6 | `FakePlaidGateway` and the spec harness |
| 7 | Pure `PlaidFeed::WebhookVerifier` |
| 8 | `PlaidFeed::Sync` (insert, claim, modify, remove, flag, rules, cursor) |
| 9 | `PlaidSyncJob`, retries, item status, daily schedule |
| 10 | CSV preview "Already synced from bank" and hash stamping |
| 11 | Connect a bank (Link), item page, Sync now, Remove, Banks nav |
| 12 | Assignment to owned books (new, attach with cutoff, skip) |
| 13 | Reconnect in update mode, dashboard banner, account status line |
| 14 | Verified webhooks |
| 15 | Needs review (inbox, household inbox, filter, dashboard) |
| 16 | Demo Bank in `demo:seed` |
| 17 | System spec, README/env, verification, stacked PR, acceptance steps |
