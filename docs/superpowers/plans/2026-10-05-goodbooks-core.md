# goodbooks Core (Sub-project 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the goodbooks core: a self-hosted Rails app where a household tracks income and expenses per business (manual + CSV accounts), categorizes them through a rules-driven inbox, logs mileage, runs P&L / Schedule C / export reports, and shares access by role, all behind mandatory TOTP 2FA, shipped as one Docker container on SQLite.

**Architecture:** Rails 8 monolith, server-rendered with Hotwire. Pure-Ruby domain objects (`Money`, `RuleEngine`, `CsvImport::Parser`, report calculators) hold the logic and are unit-tested without the DB. Controllers are thin, and every business-scoped request goes through one `BusinessScoped` concern that resolves the business via the user's memberships (404 for non-members) and checks role (403 for insufficient role).

**Tech Stack:** Ruby 4.0.7, Rails 8.1.x (8.1.4+), SQLite (WAL), Solid Queue, Hotwire, Propshaft, Importmap, Active Storage (local disk), Active Record Encryption, `rotp`, `rqrcode`, RSpec, FactoryBot, Capybara (rack_test; headless Chrome via Selenium for JS specs), WebMock, SortableJS (drag-and-drop rule ordering).

**Spec:** `docs/superpowers/specs/2026-10-05-goodbooks-design.md` (sections 1–5 apply to this plan; 6–10 are later sub-projects).

## Global Constraints

- Ruby 4.0.7 (`.ruby-version`), Rails `~> 8.1.4`, SQLite only. No Postgres, no Redis.
- Ruby 4.0.7 lives at `~/.rubies/ruby-4.0.7` and no version manager is installed. **Every shell command in this plan runs after `export PATH="$HOME/.rubies/ruby-4.0.7/bin:$PATH"`** (in a single Bash call, prefix the command with it). Check with `ruby -v` → `ruby 4.0.7`.
- All money is a signed integer number of cents in a column named `*_cents`. Never floats, never decimals.
- Percentages are integer basis points (`5000` = 50%). Mileage is integer tenths of a mile (`miles_tenths`). The mileage rate is integer tenths of a cent (72.5¢ → `725`).
- Rounding happens only in `Money.round_rational` (half away from zero), once per line item, on a `Rational`.
- `Transaction#amount_cents`: positive = money into the account, negative = money out.
- Non-member access to a business-scoped record → 404. Insufficient role → 403. Household-level screens → 404 unless the user has a membership on every business.
- Never name an association or method `transaction` (it would shadow `ActiveRecord::Base#transaction`). The model class is `Transaction`. Wrap DB transactions in `ApplicationRecord.transaction`.
- Passwords are at least 12 characters. 2FA is mandatory for every user.
- Test output must be clean: a passing `bundle exec rspec` prints only the RSpec reporter's output. Deprecations raise in test.
- TDD: every task writes the failing spec first.
- Formatting: single spaces in data literals (no column alignment).
- `bin/rails demo:seed` raises in production.

## Review Focus

1. **CSV files from real banks**: a UTF-8 BOM, `\r\n` line endings, blank trailing lines, and quoted amounts like `"1,500.00"` must all parse; blank lines are ignored, not reported as errors. (Pinned in Task 13.)
2. **Re-importing the same or an overlapping statement** must create zero duplicates, while two genuinely identical same-day rows in one file both import. (Pinned in Tasks 13 and 14.)
3. **Money typed by humans** (`$1,234.50`, `(5.00)`, `-5`, `.5`, `abc`, `1.234`, `--5`) parses exactly or produces a validation error. It never silently becomes 0. (Pinned in Tasks 2 and 9.)
4. **A viewer (the accountant) sending crafted write requests** gets 403 on every write endpoint, and a user missing a membership on any one business gets 404 on household screens. (Pinned in each controller task and Task 17.)
5. **Reusing a TOTP code** (replay within the same 30-second window) is rejected. **Date ranges include their end date** (a Dec 31 transaction is in the year's report). (Pinned in Tasks 3 and 16.)

## File Map

```
app/models/money.rb                         Money value object (pure)
app/models/concerns/money_attribute.rb      money_attribute :amount → amount_cents with parse errors
app/models/user.rb, user/two_factor.rb      auth + TOTP + recovery codes
app/models/{household,person,business,membership}.rb
app/models/{account,category,transaction,rule,mileage_entry,tax_parameters,invite,invite_grant}.rb
app/models/schedule_c.rb, category_template.rb
app/models/csv_import.rb, csv_import/{mapping,parser,preview}.rb
app/models/rule_engine.rb                   pure matching
app/models/distance.rb, mileage_deduction.rb
app/models/transaction_filter.rb
app/models/reports/*.rb                     pure calculators + loaders + CSV writers
app/services/{business_provisioner,rule_applier}.rb
app/forms/setup_form.rb
app/controllers/concerns/{authentication,business_scoped,date_range_params}.rb
app/controllers/*                           one controller per resource
app/jobs/database_backup_job.rb
lib/demo_seeder.rb, lib/tasks/demo.rake
docker-compose.yml, .env.example, README.md
```

---

### Task 1: Scaffold the Rails app with RSpec

**Files:**
- Create: the Rails app in the repo root (via `rails new`)
- Modify: `Gemfile`, `config/environments/test.rb`, `config/environments/development.rb`, `spec/rails_helper.rb`
- Create: `spec/support/factory_bot.rb`, `spec/requests/health_spec.rb`

**Interfaces:**
- Produces: a booting Rails 8.1 app named `goodbooks`, RSpec with FactoryBot, WebMock blocking real HTTP, `spec/support/**/*.rb` auto-loaded, Active Record Encryption keys in dev/test.

- [ ] **Step 1: Install Rails and generate the app**

```bash
cd /Users/AlexRoot-Roatch/current-projects/goodbooks
export PATH="$HOME/.rubies/ruby-4.0.7/bin:$PATH"
ruby -v   # must print ruby 4.0.7
gem install rails -v "~> 8.1.4" --no-document
RAILS_VERSION=$(ruby -e 'puts Gem::Specification.find_all_by_name("rails").map(&:version).select { _1.segments.first(2) == [8, 1] }.max')
rails _${RAILS_VERSION}_ new . --name=goodbooks --database=sqlite3 --skip-test --skip-system-test --skip-jbuilder --skip-kamal --force
```

`--force` only overwrites files the generator creates; `docs/` is untouched. Confirm `cat .ruby-version` prints `4.0.7` (write `4.0.7` into it if not).

- [ ] **Step 2: Add gems**

Append to `Gemfile`:

```ruby
gem "bcrypt", "~> 3.1.7"
gem "rotp", "~> 6.3"
gem "rqrcode", "~> 2.2"

group :development, :test do
  gem "rspec-rails", "~> 7.1"
  gem "factory_bot_rails", "~> 6.4"
end

group :test do
  gem "capybara", "~> 3.40"
  gem "webmock", "~> 3.24"
end
```

If `Gemfile` already contains a commented `# gem "bcrypt"` line, delete that line instead of leaving a duplicate. Then:

```bash
bundle install
bin/rails generate rspec:install
mkdir -p spec/support spec/factories
```

- [ ] **Step 3: Configure RSpec**

In `spec/rails_helper.rb`, uncomment the line that loads support files so it reads:

```ruby
Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }
```

Add right after `require "rspec/rails"`:

```ruby
require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)
```

Inside `RSpec.configure do |config|` add:

```ruby
  config.include ActiveSupport::Testing::TimeHelpers
  config.before(:each, type: :system) { driven_by :rack_test }
```

Create `spec/support/factory_bot.rb`:

```ruby
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
```

- [ ] **Step 4: Make the test environment strict and quiet, and set dev/test encryption keys**

In `config/environments/test.rb` set (replace existing values where present):

```ruby
  config.active_support.deprecation = :raise
  config.active_job.queue_adapter = :test
  config.active_record.encryption.primary_key = "test-primary-key-goodbooks-0000000000"
  config.active_record.encryption.deterministic_key = "test-deterministic-key-goodbooks-000000"
  config.active_record.encryption.key_derivation_salt = "test-key-derivation-salt-goodbooks-0000"
```

In `config/environments/development.rb` add:

```ruby
  config.active_record.encryption.primary_key = "dev-primary-key-goodbooks-00000000000"
  config.active_record.encryption.deterministic_key = "dev-deterministic-key-goodbooks-0000000"
  config.active_record.encryption.key_derivation_salt = "dev-key-derivation-salt-goodbooks-00000"
```

- [ ] **Step 5: Write the failing smoke spec**

`spec/requests/health_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Health check" do
  it "responds OK at /up" do
    get "/up"
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 6: Run it**

Run: `bin/rails db:prepare && bundle exec rspec`
Expected: `1 example, 0 failures` and nothing else besides the RSpec reporter. (`/up` is generated by Rails, so this passes immediately; the purpose is to prove the harness works and is quiet.) If anything else prints (warnings, logs), fix the configuration before continuing.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Scaffold Rails 8.1 app with RSpec, FactoryBot, WebMock"
```

---

### Task 2: Money value object and `money_attribute`

**Files:**
- Create: `app/models/money.rb`, `app/models/concerns/money_attribute.rb`
- Test: `spec/models/money_spec.rb`, `spec/models/concerns/money_attribute_spec.rb`

**Interfaces:**
- Produces:
  - `Money.new(cents)`, `#cents`, `#to_s` → `"$1,234.56"` / `"-$0.05"`, `#to_input` → `"1234.56"` / `"-0.05"`, `Comparable`
  - `Money.parse(string) → Money`, raises `Money::ParseError` (message is the validation text)
  - `Money.round_rational(numeric) → Integer` (half away from zero)
  - `MoneyAttribute` concern: `money_attribute :amount, allow_blank: false` defines `amount` (string for forms), `amount=` (parses into `amount_cents`), and a validation adding the parse error to `:amount`

- [ ] **Step 1: Write the failing Money spec**

`spec/models/money_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Money do
  describe ".parse" do
    {
      "12" => 1200,
      "12.5" => 1250,
      "12.34" => 1234,
      "$1,234.56" => 123456,
      "-5.00" => -500,
      "(5.00)" => -500,
      "($1,000)" => -100000,
      "$-5" => -500,
      ".5" => 50,
      " 7 " => 700,
      "0" => 0
    }.each do |input, cents|
      it "parses #{input.inspect} as #{cents} cents" do
        expect(Money.parse(input).cents).to eq(cents)
      end
    end

    ["", "   ", nil, "abc", "1.234", "--5", "1.2.3", "$", "12a", "(-5)"].each do |input|
      it "rejects #{input.inspect}" do
        expect { Money.parse(input) }.to raise_error(Money::ParseError)
      end
    end

    it "says blank input can't be blank" do
      expect { Money.parse("") }.to raise_error(Money::ParseError, "can't be blank")
    end

    it "says garbage is not a valid amount" do
      expect { Money.parse("abc") }.to raise_error(Money::ParseError, "is not a valid amount")
    end
  end

  describe "#to_s" do
    it { expect(Money.new(123456).to_s).to eq("$1,234.56") }
    it { expect(Money.new(-5).to_s).to eq("-$0.05") }
    it { expect(Money.new(0).to_s).to eq("$0.00") }
    it { expect(Money.new(100_000_000).to_s).to eq("$1,000,000.00") }
  end

  describe "#to_input" do
    it { expect(Money.new(-123456).to_input).to eq("-1234.56") }
    it { expect(Money.new(7).to_input).to eq("0.07") }
  end

  describe ".round_rational" do
    it { expect(Money.round_rational(Rational(5, 2))).to eq(3) }
    it { expect(Money.round_rational(Rational(-5, 2))).to eq(-3) }
    it { expect(Money.round_rational(Rational(249, 100))).to eq(2) }
    it { expect(Money.round_rational(Rational(-249, 100))).to eq(-2) }
    it { expect(Money.round_rational(7)).to eq(7) }
  end

  it "compares by cents" do
    expect(Money.new(5)).to eq(Money.new(5))
    expect(Money.new(5)).to be < Money.new(6)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/models/money_spec.rb`
Expected: FAIL with `uninitialized constant Money`.

- [ ] **Step 3: Implement Money**

`app/models/money.rb`:

```ruby
class Money
  include Comparable

  class ParseError < ArgumentError; end

  attr_reader :cents

  def self.round_rational(value)
    rational = value.to_r
    sign = rational.negative? ? -1 : 1
    sign * (rational.abs + Rational(1, 2)).floor
  end

  def self.parse(input)
    text = input.to_s.strip
    raise ParseError, "can't be blank" if text.empty?
    raise ParseError, "is not a valid amount" if text.count("-") > 1

    negative = false
    if (wrapped = text.match(/\A\((.*)\)\z/))
      raise ParseError, "is not a valid amount" if wrapped[1].include?("-")
      negative = true
      text = wrapped[1].strip
    end
    if text.start_with?("-")
      negative = true
      text = text.delete_prefix("-").strip
    end
    text = text.delete_prefix("$").delete(",")
    if text.start_with?("-")
      negative = true
      text = text.delete_prefix("-")
    end

    match = text.match(/\A(\d*)(?:\.(\d{1,2}))?\z/)
    raise ParseError, "is not a valid amount" if match.nil? || (match[1].empty? && match[2].nil?)

    cents = match[1].to_i * 100 + match[2].to_s.ljust(2, "0").to_i
    new(negative ? -cents : cents)
  end

  def initialize(cents)
    @cents = Integer(cents)
  end

  def <=>(other)
    cents <=> other.cents if other.is_a?(Money)
  end

  def to_s
    "#{"-" if cents.negative?}$#{grouped_dollars}.#{padded_cents}"
  end

  def to_input
    "#{"-" if cents.negative?}#{cents.abs / 100}.#{padded_cents}"
  end

  private

  def grouped_dollars
    (cents.abs / 100).to_s.reverse.scan(/\d{1,3}/).join(",").reverse
  end

  def padded_cents
    format("%02d", cents.abs % 100)
  end
end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/models/money_spec.rb`
Expected: PASS, all examples.

- [ ] **Step 5: Write the failing MoneyAttribute spec**

`spec/models/concerns/money_attribute_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe MoneyAttribute do
  let(:model_class) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include ActiveModel::Validations
      attribute :amount_cents, :integer
      attribute :limit_cents, :integer
      include MoneyAttribute
      money_attribute :amount
      money_attribute :limit, allow_blank: true

      def self.name = "Thing"

      def [](key) = public_send(key)
      def []=(key, value)
        public_send("#{key}=", value)
      end
    end
  end

  it "parses input into cents" do
    thing = model_class.new(amount: "$1,234.50")
    expect(thing.amount_cents).to eq(123450)
    expect(thing).to be_valid
  end

  it "keeps the raw input for redisplay and reports the parse error" do
    thing = model_class.new(amount: "abc")
    expect(thing.amount).to eq("abc")
    expect(thing.amount_cents).to be_nil
    expect(thing).not_to be_valid
    expect(thing.errors[:amount]).to include("is not a valid amount")
  end

  it "formats stored cents for forms when no input was given" do
    thing = model_class.new(amount_cents: -500)
    expect(thing.amount).to eq("-5.00")
  end

  it "allows blank when configured" do
    thing = model_class.new(amount: "1", limit: "")
    expect(thing.limit_cents).to be_nil
    expect(thing).to be_valid
  end

  it "rejects blank when not configured" do
    thing = model_class.new(amount: "")
    expect(thing).not_to be_valid
    expect(thing.errors[:amount]).to include("can't be blank")
  end
end
```

- [ ] **Step 6: Run it to verify it fails**

Run: `bundle exec rspec spec/models/concerns/money_attribute_spec.rb`
Expected: FAIL with `uninitialized constant MoneyAttribute`.

- [ ] **Step 7: Implement the concern**

`app/models/concerns/money_attribute.rb`:

```ruby
module MoneyAttribute
  extend ActiveSupport::Concern

  class_methods do
    def money_attribute(name, allow_blank: false)
      cents = "#{name}_cents"
      input_ivar = "@#{name}_input"
      error_ivar = "@#{name}_parse_error"

      define_method(name) do
        if instance_variable_defined?(input_ivar)
          instance_variable_get(input_ivar)
        elsif self[cents]
          Money.new(self[cents]).to_input
        end
      end

      define_method("#{name}=") do |input|
        instance_variable_set(input_ivar, input)
        instance_variable_set(error_ivar, nil)
        self[cents] = allow_blank && input.to_s.strip.empty? ? nil : Money.parse(input).cents
      rescue Money::ParseError => e
        self[cents] = nil
        instance_variable_set(error_ivar, e.message)
      end

      validate do
        message = instance_variable_defined?(error_ivar) && instance_variable_get(error_ivar)
        errors.add(name, message) if message
      end
    end
  end
end
```

- [ ] **Step 8: Run both specs**

Run: `bundle exec rspec spec/models`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add Money value object and money_attribute concern"
```

---

### Task 3: Authentication with mandatory TOTP 2FA

**Files:**
- Generate: `bin/rails generate authentication` (User, Session, Current, Authentication concern, SessionsController, views)
- Delete: password-reset pieces the generator adds (`app/controllers/passwords_controller.rb`, `app/mailers/passwords_mailer.rb`, `app/views/passwords/`, `app/views/passwords_mailer/`)
- Create: `db/migrate/*_add_profile_and_two_factor_to_users.rb`, `app/models/user/two_factor.rb`, `app/controllers/two_factors_controller.rb`, `app/controllers/two_factor_setups_controller.rb`, `app/controllers/dashboards_controller.rb`, views for those, `spec/factories/users.rb`, `spec/support/auth_helpers.rb`
- Modify: `app/models/user.rb`, `app/controllers/concerns/authentication.rb`, `app/controllers/sessions_controller.rb`, `app/views/sessions/new.html.erb`, `app/views/layouts/application.html.erb`, `config/routes.rb`
- Test: `spec/models/user_spec.rb`, `spec/requests/authentication_spec.rb`

**Interfaces:**
- Produces:
  - `User` columns: `email_address`, `password_digest`, `name`, `household_owner:boolean`, `otp_secret` (encrypted), `otp_enabled_at`, `otp_last_verified_at:integer`, `recovery_code_digests:json`
  - `User#totp → ROTP::TOTP`, `#otp_enabled?`, `#otp_provisioning_uri`, `#generate_otp_secret!`, `#verify_otp(code) → bool`, `#enable_otp! → Array<String>` (recovery codes), `#consume_recovery_code(code) → bool`
  - `Authentication` concern additions: `begin_two_factor(user)` (stores the pending user and redirects to the challenge or the setup), `pending_user → User | nil` (expires after 10 minutes), `complete_two_factor(user)`
  - Routes: `new_session_path`, `session_path`, `new_two_factor_path`, `two_factor_path`, `new_two_factor_setup_path`, `two_factor_setup_path`, `root_path` (`dashboards#show`)
  - Spec helpers: `AuthHelpers::PASSWORD`, `sign_in_as(user)` (request specs), `system_sign_in_as(user)` (system specs)

- [ ] **Step 1: Run the generator and remove password reset**

```bash
bin/rails generate authentication
rm -f app/controllers/passwords_controller.rb app/mailers/passwords_mailer.rb
rm -rf app/views/passwords app/views/passwords_mailer
grep -rn "password" config/routes.rb app/views/sessions
```

In `config/routes.rb` delete the `resources :passwords, param: :token` line. In `app/views/sessions/new.html.erb` delete the "Forgot password?" link. Re-run the grep; only `password` form fields may remain.

- [ ] **Step 2: Add the migration**

```bash
bin/rails generate migration AddProfileAndTwoFactorToUsers
```

Fill it in:

```ruby
class AddProfileAndTwoFactorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string, null: false, default: ""
    add_column :users, :household_owner, :boolean, null: false, default: false
    add_column :users, :otp_secret, :string
    add_column :users, :otp_enabled_at, :datetime
    add_column :users, :otp_last_verified_at, :integer
    add_column :users, :recovery_code_digests, :json, null: false, default: []
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 3: Write the user factory and auth helpers**

`spec/factories/users.rb`:

```ruby
FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    name { "Test User" }
    password { AuthHelpers::PASSWORD }
    otp_secret { ROTP::Base32.random }
    otp_enabled_at { Time.current }

    trait :without_otp do
      otp_secret { nil }
      otp_enabled_at { nil }
    end

    trait :household_owner do
      household_owner { true }
    end
  end
end
```

`spec/support/auth_helpers.rb`:

```ruby
module AuthHelpers
  PASSWORD = "correct horse battery"

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: PASSWORD }
    post two_factor_path, params: { code: user.totp.now }
  end
end

module SystemAuthHelpers
  def system_sign_in_as(user)
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: AuthHelpers::PASSWORD
    click_on "Sign in"
    fill_in "code", with: user.totp.now
    click_on "Verify"
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
  config.include SystemAuthHelpers, type: :system
end
```

- [ ] **Step 4: Write the failing User two-factor spec**

`spec/models/user_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe User do
  describe "validations" do
    it "requires a password of at least 12 characters" do
      user = build(:user, password: "short")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "normalizes the email address" do
      expect(create(:user, email_address: " Pat@Example.COM ").email_address).to eq("pat@example.com")
    end

    it "requires a name" do
      expect(build(:user, name: "")).not_to be_valid
    end
  end

  describe "#verify_otp" do
    let(:user) { create(:user) }

    it "accepts the current code" do
      expect(user.verify_otp(user.totp.now)).to be(true)
    end

    it "rejects a wrong code" do
      wrong = user.totp.now == "000000" ? "111111" : "000000"
      expect(user.verify_otp(wrong)).to be(false)
    end

    it "rejects a replayed code" do
      freeze_time do
        code = user.totp.now
        expect(user.verify_otp(code)).to be(true)
        expect(user.reload.verify_otp(code)).to be(false)
      end
    end

    it "rejects when no secret is set" do
      expect(build(:user, :without_otp).verify_otp("123456")).to be(false)
    end
  end

  describe "#enable_otp! and recovery codes" do
    let(:user) { create(:user, :without_otp, otp_secret: ROTP::Base32.random) }

    it "enables 2FA and returns 10 single-use recovery codes" do
      codes = user.enable_otp!
      expect(user.reload).to be_otp_enabled
      expect(codes.size).to eq(10)
      expect(codes.uniq.size).to eq(10)
      expect(user.consume_recovery_code(codes.first.upcase)).to be(true)
      expect(user.reload.consume_recovery_code(codes.first)).to be(false)
      expect(user.recovery_code_digests.size).to eq(9)
    end

    it "does not store recovery codes in plain text" do
      codes = user.enable_otp!
      expect(user.reload.recovery_code_digests).not_to include(codes.first)
    end
  end

  it "encrypts the OTP secret at rest" do
    user = create(:user)
    raw = User.connection.select_value("SELECT otp_secret FROM users WHERE id = #{user.id}")
    expect(raw).not_to eq(user.otp_secret)
  end
end
```

- [ ] **Step 5: Run it to verify it fails**

Run: `bundle exec rspec spec/models/user_spec.rb`
Expected: FAIL with `NoMethodError: undefined method 'totp'` (and the name/length validations failing).

- [ ] **Step 6: Implement the User model and TwoFactor module**

`app/models/user/two_factor.rb`:

```ruby
module User::TwoFactor
  extend ActiveSupport::Concern

  RECOVERY_CODE_COUNT = 10

  included do
    encrypts :otp_secret
  end

  def otp_enabled? = otp_enabled_at.present?

  def totp = ROTP::TOTP.new(otp_secret, issuer: "goodbooks")

  def otp_provisioning_uri = totp.provisioning_uri(email_address)

  def generate_otp_secret!
    update!(otp_secret: ROTP::Base32.random)
  end

  def verify_otp(code)
    return false if otp_secret.blank? || code.blank?

    timestamp = totp.verify(code.to_s.gsub(/\s/, ""), drift_behind: 30, after: otp_last_verified_at)
    return false unless timestamp

    update!(otp_last_verified_at: timestamp)
    true
  end

  def enable_otp!
    codes = Array.new(RECOVERY_CODE_COUNT) { SecureRandom.alphanumeric(10).downcase }
    update!(otp_enabled_at: Time.current, recovery_code_digests: codes.map { |c| BCrypt::Password.create(c, cost: bcrypt_cost) })
    codes
  end

  def consume_recovery_code(code)
    normalized = code.to_s.strip.downcase
    return false if normalized.empty?

    digest = recovery_code_digests.find { |d| BCrypt::Password.new(d) == normalized }
    return false unless digest

    update!(recovery_code_digests: recovery_code_digests - [digest])
    true
  end

  private

  def bcrypt_cost
    ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
  end
end
```

Replace `app/models/user.rb` with:

```ruby
class User < ApplicationRecord
  include TwoFactor

  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :name, presence: true
  validates :password, length: { minimum: 12 }, allow_nil: true
end
```

- [ ] **Step 7: Run the model spec**

Run: `bundle exec rspec spec/models/user_spec.rb`
Expected: PASS.

- [ ] **Step 8: Write the failing request spec for the login flow**

`spec/requests/authentication_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Authentication" do
  let(:user) { create(:user) }

  def log_in_password(email: user.email_address, password: AuthHelpers::PASSWORD)
    post session_path, params: { email_address: email, password: password }
  end

  it "redirects anonymous visitors to the login page" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "rejects a wrong password" do
    log_in_password(password: "wrong password!!")
    expect(response).to redirect_to(new_session_path)
  end

  it "requires a TOTP code after the password" do
    log_in_password
    expect(response).to redirect_to(new_two_factor_path)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "signs in after a correct code" do
    log_in_password
    post two_factor_path, params: { code: user.totp.now }
    expect(response).to redirect_to(root_url)
    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "rejects a wrong code" do
    log_in_password
    wrong = user.totp.now == "000000" ? "111111" : "000000"
    post two_factor_path, params: { code: wrong }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "rejects a replayed code on a second login in the same window" do
    freeze_time do
      code = user.totp.now
      log_in_password
      post two_factor_path, params: { code: code }
      delete session_path
      log_in_password
      post two_factor_path, params: { code: code }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "accepts a recovery code once" do
    codes = user.enable_otp!
    log_in_password
    post two_factor_path, params: { code: codes.first }
    expect(response).to redirect_to(root_url)
    delete session_path
    log_in_password
    post two_factor_path, params: { code: codes.first }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "expires the pending login after 10 minutes" do
    log_in_password
    travel 11.minutes
    post two_factor_path, params: { code: user.totp.now }
    expect(response).to redirect_to(new_session_path)
  end

  it "does not allow the code page without a password step" do
    get new_two_factor_path
    expect(response).to redirect_to(new_session_path)
  end

  describe "first-time enrollment" do
    let(:user) { create(:user, :without_otp) }

    it "sends a user without 2FA to setup, then signs them in with recovery codes shown" do
      log_in_password
      expect(response).to redirect_to(new_two_factor_setup_path)
      get new_two_factor_setup_path
      expect(response.body).to include("<svg")
      user.reload
      post two_factor_setup_path, params: { code: user.totp.now }
      expect(response).to have_http_status(:ok)
      expect(response.body.scan(/<li class="recovery-code">/).size).to eq(10)
      expect(user.reload).to be_otp_enabled
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "keeps the same secret across setup page reloads" do
      log_in_password
      get new_two_factor_setup_path
      secret = user.reload.otp_secret
      get new_two_factor_setup_path
      expect(user.reload.otp_secret).to eq(secret)
    end

    it "rejects a wrong setup code" do
      log_in_password
      get new_two_factor_setup_path
      post two_factor_setup_path, params: { code: "abcdef" }
      expect(response).to redirect_to(new_two_factor_setup_path)
      expect(user.reload).not_to be_otp_enabled
    end
  end

  it "keeps enrolled users out of setup" do
    log_in_password
    get new_two_factor_setup_path
    expect(response).to redirect_to(new_session_path)
  end
end
```

- [ ] **Step 9: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/authentication_spec.rb`
Expected: FAIL (`root_path` undefined / no two_factor routes).

- [ ] **Step 10: Routes**

`config/routes.rb` (keep the generated `/up` and PWA lines):

```ruby
Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resource :two_factor, only: %i[new create]
  resource :two_factor_setup, only: %i[new create]

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboards#show"
end
```

- [ ] **Step 11: Extend the Authentication concern**

Open `app/controllers/concerns/authentication.rb`. Change `start_new_session_for` so the cookie lasts 30 days instead of being permanent:

```ruby
    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = { value: session.id, httponly: true, same_site: :lax, expires: 30.days }
      end
    end
```

Add these private methods to the concern:

```ruby
    PENDING_TTL = 10.minutes

    def begin_two_factor(user)
      return_to = session[:return_to_after_authenticating]
      reset_session
      session[:return_to_after_authenticating] = return_to if return_to
      session[:pending_user_id] = user.id
      session[:pending_at] = Time.current.to_i
      redirect_to user.otp_enabled? ? new_two_factor_path : new_two_factor_setup_path
    end

    def pending_user
      return if session[:pending_user_id].blank?
      return if session[:pending_at].to_i < PENDING_TTL.ago.to_i

      User.find_by(id: session[:pending_user_id])
    end

    def complete_two_factor(user)
      session.delete(:pending_user_id)
      session.delete(:pending_at)
      start_new_session_for(user)
    end
```

- [ ] **Step 12: Sessions controller uses the 2FA step**

In `app/controllers/sessions_controller.rb` replace `create` with:

```ruby
  def create
    if (user = User.authenticate_by(params.permit(:email_address, :password)))
      begin_two_factor(user)
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end
```

- [ ] **Step 13: Two-factor controllers**

`app/controllers/two_factors_controller.rb`:

```ruby
class TwoFactorsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  before_action :require_pending_user

  def new
  end

  def create
    if @user.verify_otp(params[:code]) || @user.consume_recovery_code(params[:code])
      complete_two_factor(@user)
      redirect_to after_authentication_url
    else
      flash.now[:alert] = "That code didn't work."
      render :new, status: :unprocessable_entity
    end
  end

  private

  def require_pending_user
    @user = pending_user
    redirect_to new_session_path unless @user&.otp_enabled?
  end
end
```

`app/controllers/two_factor_setups_controller.rb`:

```ruby
class TwoFactorSetupsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  before_action :require_pending_user

  def new
    @user.generate_otp_secret! if @user.otp_secret.blank?
    @qr_svg = RQRCode::QRCode.new(@user.otp_provisioning_uri).as_svg(module_size: 4, use_path: true)
  end

  def create
    if @user.verify_otp(params[:code])
      @recovery_codes = @user.enable_otp!
      complete_two_factor(@user)
      render :recovery_codes
    else
      redirect_to new_two_factor_setup_path, alert: "That code didn't work. Try again."
    end
  end

  private

  def require_pending_user
    @user = pending_user
    redirect_to new_session_path if @user.nil? || @user.otp_enabled?
  end
end
```

`app/controllers/dashboards_controller.rb`:

```ruby
class DashboardsController < ApplicationController
  def show
  end
end
```

- [ ] **Step 14: Views**

`app/views/two_factors/new.html.erb`:

```erb
<h1>Two-factor verification</h1>
<%= form_with url: two_factor_path do |f| %>
  <%= f.label :code, "Authenticator code or recovery code" %>
  <%= f.text_field :code, autocomplete: "one-time-code", autofocus: true, required: true %>
  <%= f.submit "Verify" %>
<% end %>
```

`app/views/two_factor_setups/new.html.erb`:

```erb
<h1>Set up two-factor authentication</h1>
<p>Scan this with your authenticator app, then enter the 6-digit code.</p>
<div class="qr"><%= raw @qr_svg %></div>
<p>Or enter this key manually: <code><%= @user.otp_secret %></code></p>
<%= form_with url: two_factor_setup_path do |f| %>
  <%= f.label :code, "Code" %>
  <%= f.text_field :code, autocomplete: "one-time-code", autofocus: true, required: true %>
  <%= f.submit "Verify" %>
<% end %>
```

`app/views/two_factor_setups/recovery_codes.html.erb`:

```erb
<h1>Save your recovery codes</h1>
<p>Each code works once if you lose your authenticator. They won't be shown again.</p>
<ul class="recovery-codes">
  <% @recovery_codes.each do |code| %>
    <li class="recovery-code"><code><%= code %></code></li>
  <% end %>
</ul>
<%= link_to "Continue", root_path %>
```

`app/views/dashboards/show.html.erb`:

```erb
<h1>goodbooks</h1>
<p>Signed in as <%= Current.user.name %>.</p>
```

Replace the `<body>` of `app/views/layouts/application.html.erb` with:

```erb
  <body>
    <header class="site-header no-print">
      <%= link_to "goodbooks", root_path, class: "brand" %>
      <% if authenticated? %>
        <nav class="site-nav">
          <%= button_to "Sign out", session_path, method: :delete %>
        </nav>
      <% end %>
    </header>
    <main>
      <% flash.each do |type, message| %>
        <p class="flash flash-<%= type %>"><%= message %></p>
      <% end %>
      <%= yield %>
    </main>
  </body>
```

Make sure the generated sessions form's submit button label is `Sign in` and its fields are named `email_address` and `password` (the system helper relies on these).

- [ ] **Step 15: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS, clean output.

- [ ] **Step 16: Commit**

```bash
git add -A
git commit -m "Add authentication with mandatory TOTP 2FA and recovery codes"
```

---

### Task 4: Household, people, businesses, memberships

**Files:**
- Create: migrations for `households`, `people`, `businesses`, `memberships`; `app/models/{household,person,business,membership}.rb`; `spec/factories/{households,people,businesses,memberships}.rb`; `spec/support/membership_helpers.rb`
- Modify: `app/models/user.rb`
- Test: `spec/models/person_spec.rb`, `spec/models/membership_spec.rb`, `spec/models/user_access_spec.rb`

**Interfaces:**
- Produces:
  - `Household.instance → Household` (raises if none)
  - `Person` (`household`, `name`, optional `user`); at most 2 per household
  - `Business` (`household`, `person`, `name`, `archived_at`), `Business.active`, `has_many :memberships`
  - `Membership` (`user`, `business`, `role` in `owner|editor|viewer`), `#can_edit?`, `Membership::RANK = { "viewer" => 0, "editor" => 1, "owner" => 2 }`
  - `User#memberships`, `#person`, `#accessible_businesses → Relation<Business>`, `#membership_for(business) → Membership | nil`, `#can_view_household? → bool`
  - Spec helper: `user_with_role(role, business, **user_attrs) → User`

- [ ] **Step 1: Migrations**

```bash
bin/rails generate migration CreateHouseholds
bin/rails generate migration CreatePeople
bin/rails generate migration CreateBusinesses
bin/rails generate migration CreateMemberships
```

Fill them in (one per file, in this order):

```ruby
class CreateHouseholds < ActiveRecord::Migration[8.1]
  def change
    create_table :households do |t|
      t.string :name, null: false
      t.timestamps
    end
  end
end
```

```ruby
class CreatePeople < ActiveRecord::Migration[8.1]
  def change
    create_table :people do |t|
      t.references :household, null: false, foreign_key: true
      t.references :user, foreign_key: true, index: { unique: true }
      t.string :name, null: false
      t.timestamps
    end
  end
end
```

```ruby
class CreateBusinesses < ActiveRecord::Migration[8.1]
  def change
    create_table :businesses do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.string :name, null: false
      t.datetime :archived_at
      t.timestamps
    end
  end
end
```

```ruby
class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
    add_index :memberships, %i[user_id business_id], unique: true
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Factories and helper**

`spec/factories/households.rb`:

```ruby
FactoryBot.define do
  factory :household do
    name { "Test Household" }
  end
end
```

`spec/factories/people.rb`:

```ruby
FactoryBot.define do
  factory :person do
    household { Household.first || association(:household) }
    sequence(:name) { |n| "Person #{n}" }
  end
end
```

`spec/factories/businesses.rb`:

```ruby
FactoryBot.define do
  factory :business do
    household { Household.first || association(:household) }
    person { household.people.first || association(:person, household: household) }
    sequence(:name) { |n| "Business #{n}" }
  end
end
```

`spec/factories/memberships.rb`:

```ruby
FactoryBot.define do
  factory :membership do
    user
    business
    role { "viewer" }
  end
end
```

`spec/support/membership_helpers.rb`:

```ruby
module MembershipHelpers
  def user_with_role(role, business, **attrs)
    create(:user, **attrs).tap { |user| create(:membership, user: user, business: business, role: role) }
  end
end

RSpec.configure do |config|
  config.include MembershipHelpers
end
```

- [ ] **Step 3: Write failing model specs**

`spec/models/person_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Person do
  it "allows at most two people per household" do
    household = create(:household)
    create(:person, household: household)
    create(:person, household: household)
    third = build(:person, household: household)
    expect(third).not_to be_valid
    expect(third.errors[:base]).to include("A household has at most two people")
  end

  it "links to at most one user" do
    user = create(:user)
    create(:person, user: user)
    expect(build(:person, user: user)).not_to be_valid
  end
end
```

`spec/models/membership_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Membership do
  it "rejects unknown roles" do
    expect(build(:membership, role: "admin")).not_to be_valid
  end

  it "is unique per user and business" do
    existing = create(:membership)
    expect(build(:membership, user: existing.user, business: existing.business)).not_to be_valid
  end

  it "lets owners and editors edit" do
    expect(build(:membership, role: "owner").can_edit?).to be(true)
    expect(build(:membership, role: "editor").can_edit?).to be(true)
    expect(build(:membership, role: "viewer").can_edit?).to be(false)
  end
end
```

`spec/models/user_access_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "User business access" do
  let!(:mine) { create(:business) }
  let!(:theirs) { create(:business) }
  let(:user) { user_with_role("viewer", mine) }

  it "lists only businesses with a membership" do
    expect(user.accessible_businesses).to contain_exactly(mine)
  end

  it "finds the membership for a business" do
    expect(user.membership_for(mine).role).to eq("viewer")
    expect(user.membership_for(theirs)).to be_nil
  end

  it "can view the household only with access to every business" do
    expect(user.can_view_household?).to be(false)
    create(:membership, user: user, business: theirs, role: "viewer")
    expect(user.reload.can_view_household?).to be(true)
  end

  it "requires the business person to be in the same household" do
    other_household = Household.create!(name: "Other")
    stranger = Person.create!(household: other_household, name: "Stranger")
    expect(build(:business, household: mine.household, person: stranger)).not_to be_valid
  end
end
```

- [ ] **Step 4: Run them to verify they fail**

Run: `bundle exec rspec spec/models/person_spec.rb spec/models/membership_spec.rb spec/models/user_access_spec.rb`
Expected: FAIL with `uninitialized constant Household` (or similar).

- [ ] **Step 5: Implement the models**

`app/models/household.rb`:

```ruby
class Household < ApplicationRecord
  has_many :people, dependent: :destroy
  has_many :businesses, dependent: :destroy

  validates :name, presence: true

  def self.instance = first!
end
```

`app/models/person.rb`:

```ruby
class Person < ApplicationRecord
  MAX_PER_HOUSEHOLD = 2

  belongs_to :household
  belongs_to :user, optional: true
  has_many :businesses, dependent: :restrict_with_error

  validates :name, presence: true
  validates :user_id, uniqueness: true, allow_nil: true
  validate :household_has_room, on: :create

  private

  def household_has_room
    return unless household && household.people.count >= MAX_PER_HOUSEHOLD

    errors.add(:base, "A household has at most two people")
  end
end
```

`app/models/business.rb`:

```ruby
class Business < ApplicationRecord
  belongs_to :household
  belongs_to :person
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  scope :active, -> { where(archived_at: nil) }

  validates :name, presence: true
  validate :person_in_household

  private

  def person_in_household
    errors.add(:person, "must belong to this household") if person && person.household_id != household_id
  end
end
```

`app/models/membership.rb`:

```ruby
class Membership < ApplicationRecord
  RANK = { "viewer" => 0, "editor" => 1, "owner" => 2 }.freeze

  belongs_to :user
  belongs_to :business

  enum :role, { owner: "owner", editor: "editor", viewer: "viewer" }, validate: true

  validates :business_id, uniqueness: { scope: :user_id }

  def can_edit? = owner? || editor?
end
```

Add to `app/models/user.rb` (inside the class):

```ruby
  has_many :memberships, dependent: :destroy
  has_one :person, dependent: :nullify

  def accessible_businesses
    Business.where(id: memberships.select(:business_id))
  end

  def membership_for(business)
    memberships.find_by(business: business)
  end

  def can_view_household?
    Business.where.not(id: memberships.select(:business_id)).none?
  end
```

- [ ] **Step 6: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add household, people, businesses, and memberships"
```

---

### Task 5: Accounts, categories, Schedule C lines, business provisioning

**Files:**
- Create: migrations for `accounts`, `categories`; `app/models/{account,category,schedule_c,category_template}.rb`; `app/services/business_provisioner.rb`; `spec/factories/{accounts,categories}.rb`
- Modify: `app/models/business.rb`
- Test: `spec/models/category_spec.rb`, `spec/services/business_provisioner_spec.rb`

**Interfaces:**
- Produces:
  - `Account` (`business`, `name`, `source` enum `manual|csv|plaid`, `kind` enum `checking|savings|credit|cash|other` with `prefix: :kind`, `csv_mapping:json`, `archived_at`), `Account.active`
  - `Category` (`business`, `name`, `kind` enum `income|expense`, `schedule_c_line`, `deductible_bps` default 10000, `archived_at`), `Category.active`, `#deductible_percent` / `#deductible_percent=` (string ↔ bps)
  - `ScheduleC::LINES` (ordered Hash code → description), `ScheduleC::INCOME_LINES`, `ScheduleC.label(code)`, `ScheduleC.options_for(kind) → [[label, code], ...]`
  - `CategoryTemplate::CATEGORIES`, `CategoryTemplate.apply_to(business)`
  - `BusinessProvisioner.call(business, owner:) → Business` (saves the business, owner membership, Cash account, template categories, in one DB transaction; raises `ActiveRecord::RecordInvalid`)
  - `Business#accounts`, `#categories`

- [ ] **Step 1: Migrations**

```bash
bin/rails generate migration CreateAccounts
bin/rails generate migration CreateCategories
```

```ruby
class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :source, null: false
      t.string :kind, null: false
      t.json :csv_mapping
      t.datetime :archived_at
      t.timestamps
    end
  end
end
```

```ruby
class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.string :schedule_c_line, null: false
      t.integer :deductible_bps, null: false, default: 10_000
      t.datetime :archived_at
      t.timestamps
    end
    add_index :categories, %i[business_id name], unique: true
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Factories**

`spec/factories/accounts.rb`:

```ruby
FactoryBot.define do
  factory :account do
    business
    sequence(:name) { |n| "Account #{n}" }
    source { "manual" }
    kind { "checking" }

    trait :csv do
      source { "csv" }
    end
  end
end
```

`spec/factories/categories.rb`:

```ruby
FactoryBot.define do
  factory :category do
    business
    sequence(:name) { |n| "Category #{n}" }
    kind { "expense" }
    schedule_c_line { "18" }

    trait :income do
      kind { "income" }
      schedule_c_line { "1" }
    end
  end
end
```

- [ ] **Step 3: Write failing specs**

`spec/models/category_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Category do
  it "requires an income line for income categories" do
    expect(build(:category, kind: "income", schedule_c_line: "18")).not_to be_valid
    expect(build(:category, kind: "income", schedule_c_line: "1")).to be_valid
  end

  it "requires an expense line for expense categories" do
    expect(build(:category, kind: "expense", schedule_c_line: "1")).not_to be_valid
  end

  it "does not allow line 30 (home office comes from sub-project 5)" do
    expect(build(:category, schedule_c_line: "30")).not_to be_valid
  end

  it "keeps deductible_bps between 0 and 10000" do
    expect(build(:category, deductible_bps: 10_001)).not_to be_valid
    expect(build(:category, deductible_bps: -1)).not_to be_valid
  end

  describe "#deductible_percent" do
    it "reads bps as a percent string" do
      expect(build(:category, deductible_bps: 5000).deductible_percent).to eq("50")
      expect(build(:category, deductible_bps: 3333).deductible_percent).to eq("33.33")
    end

    it "writes a percent string as bps" do
      category = build(:category, deductible_percent: "33.33")
      expect(category.deductible_bps).to eq(3333)
    end

    it "flags garbage" do
      category = build(:category, deductible_percent: "half")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end
  end

  it "has a unique name per business" do
    existing = create(:category)
    expect(build(:category, business: existing.business, name: existing.name)).not_to be_valid
  end
end
```

`spec/services/business_provisioner_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe BusinessProvisioner do
  let(:owner) { create(:user) }
  let(:business) { build(:business, name: "Pat Consulting") }

  it "creates the business with an owner membership, a Cash account, and template categories" do
    BusinessProvisioner.call(business, owner: owner)

    expect(business).to be_persisted
    expect(owner.membership_for(business).role).to eq("owner")
    expect(business.accounts.map { [_1.name, _1.source, _1.kind] }).to eq([["Cash", "manual", "cash"]])
    expect(business.categories.count).to eq(CategoryTemplate::CATEGORIES.size)
    expect(business.categories.find_by!(name: "Meals").deductible_bps).to eq(5000)
  end

  it "rolls back everything when the business is invalid" do
    business.name = ""
    expect { BusinessProvisioner.call(business, owner: owner) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Account.count).to eq(0)
    expect(Membership.count).to eq(0)
  end
end
```

- [ ] **Step 4: Run them to verify they fail**

Run: `bundle exec rspec spec/models/category_spec.rb spec/services/business_provisioner_spec.rb`
Expected: FAIL with `uninitialized constant Category`.

- [ ] **Step 5: Implement**

`app/models/schedule_c.rb`:

```ruby
module ScheduleC
  LINES = {
    "1" => "Gross receipts or sales",
    "2" => "Returns and allowances",
    "6" => "Other income",
    "8" => "Advertising",
    "9" => "Car and truck expenses",
    "10" => "Commissions and fees",
    "11" => "Contract labor",
    "13" => "Depreciation",
    "15" => "Insurance (other than health)",
    "16b" => "Interest (other)",
    "17" => "Legal and professional services",
    "18" => "Office expense",
    "20b" => "Rent or lease (other business property)",
    "21" => "Repairs and maintenance",
    "22" => "Supplies",
    "23" => "Taxes and licenses",
    "24a" => "Travel",
    "24b" => "Deductible meals",
    "25" => "Utilities",
    "26" => "Wages",
    "27a" => "Other expenses",
    "30" => "Business use of home"
  }.freeze

  INCOME_LINES = %w[1 2 6].freeze
  COMPUTED_LINES = %w[30].freeze
  EXPENSE_LINES = (LINES.keys - INCOME_LINES - COMPUTED_LINES).freeze

  def self.label(code) = "Line #{code}: #{LINES.fetch(code)}"

  def self.options_for(kind)
    codes = kind.to_s == "income" ? INCOME_LINES : EXPENSE_LINES
    codes.map { |code| [label(code), code] }
  end
end
```

`app/models/category_template.rb`:

```ruby
module CategoryTemplate
  CATEGORIES = [
    { name: "Sales", kind: "income", schedule_c_line: "1" },
    { name: "Refunds given", kind: "income", schedule_c_line: "2" },
    { name: "Other income", kind: "income", schedule_c_line: "6" },
    { name: "Advertising", kind: "expense", schedule_c_line: "8" },
    { name: "Parking and tolls", kind: "expense", schedule_c_line: "9" },
    { name: "Commissions and fees", kind: "expense", schedule_c_line: "10" },
    { name: "Contract labor", kind: "expense", schedule_c_line: "11" },
    { name: "Insurance", kind: "expense", schedule_c_line: "15" },
    { name: "Legal and professional", kind: "expense", schedule_c_line: "17" },
    { name: "Office expense", kind: "expense", schedule_c_line: "18" },
    { name: "Rent", kind: "expense", schedule_c_line: "20b" },
    { name: "Repairs", kind: "expense", schedule_c_line: "21" },
    { name: "Supplies", kind: "expense", schedule_c_line: "22" },
    { name: "Taxes and licenses", kind: "expense", schedule_c_line: "23" },
    { name: "Travel", kind: "expense", schedule_c_line: "24a" },
    { name: "Meals", kind: "expense", schedule_c_line: "24b", deductible_bps: 5000 },
    { name: "Utilities", kind: "expense", schedule_c_line: "25" },
    { name: "Wages", kind: "expense", schedule_c_line: "26" },
    { name: "Software", kind: "expense", schedule_c_line: "27a" },
    { name: "Phone and internet", kind: "expense", schedule_c_line: "27a" },
    { name: "Bank fees", kind: "expense", schedule_c_line: "27a" },
    { name: "Education", kind: "expense", schedule_c_line: "27a" }
  ].freeze

  def self.apply_to(business)
    CATEGORIES.each { |attrs| business.categories.create!(attrs) }
  end
end
```

`app/models/account.rb`:

```ruby
class Account < ApplicationRecord
  belongs_to :business

  enum :source, { manual: "manual", csv: "csv", plaid: "plaid" }, validate: true
  enum :kind, { checking: "checking", savings: "savings", credit: "credit", cash: "cash", other: "other" },
    validate: true, prefix: :kind

  scope :active, -> { where(archived_at: nil) }

  validates :name, presence: true

  def archived? = archived_at.present?
end
```

`app/models/category.rb`:

```ruby
class Category < ApplicationRecord
  belongs_to :business

  enum :kind, { income: "income", expense: "expense" }, validate: true

  scope :active, -> { where(archived_at: nil) }

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :deductible_bps, numericality: { only_integer: true, in: 0..10_000 }
  validate :schedule_c_line_matches_kind
  validate :deductible_percent_parses

  def deductible_percent
    return @deductible_percent_input if defined?(@deductible_percent_input)

    value = Rational(deductible_bps.to_i, 100)
    value.denominator == 1 ? value.to_i.to_s : format("%.2f", value)
  end

  def deductible_percent=(input)
    @deductible_percent_input = input
    @deductible_percent_invalid = false
    self.deductible_bps = (Rational(input.to_s.strip) * 100).round
  rescue ArgumentError, ZeroDivisionError
    @deductible_percent_invalid = true
  end

  def archived? = archived_at.present?

  private

  def schedule_c_line_matches_kind
    allowed = ScheduleC.options_for(kind).map(&:last)
    errors.add(:schedule_c_line, "is not valid for #{kind} categories") unless allowed.include?(schedule_c_line)
  end

  def deductible_percent_parses
    errors.add(:deductible_percent, "is not a number") if @deductible_percent_invalid
  end
end
```

`app/services/business_provisioner.rb`:

```ruby
class BusinessProvisioner
  def self.call(business, owner:)
    ApplicationRecord.transaction do
      business.save!
      business.memberships.create!(user: owner, role: "owner")
      business.accounts.create!(name: "Cash", source: "manual", kind: "cash")
      CategoryTemplate.apply_to(business)
    end
    business
  end
end
```

Add to `app/models/business.rb`:

```ruby
  has_many :accounts, dependent: :destroy
  has_many :categories, dependent: :destroy
```

- [ ] **Step 6: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add accounts, categories, Schedule C lines, and business provisioning"
```

---

### Task 6: First-run setup, app shell, business screens

**Files:**
- Create: `app/forms/setup_form.rb`, `app/controllers/setups_controller.rb`, `app/controllers/concerns/business_scoped.rb`, `app/controllers/businesses_controller.rb`, `app/helpers/application_helper.rb` (replace), views under `app/views/setups/`, `app/views/businesses/`, `app/assets/stylesheets/application.css` (replace)
- Modify: `app/controllers/application_controller.rb`, `app/controllers/dashboards_controller.rb`, `app/views/dashboards/show.html.erb`, `app/views/layouts/application.html.erb`, `config/routes.rb`, `spec/requests/authentication_spec.rb`
- Test: `spec/requests/setup_spec.rb`, `spec/requests/businesses_spec.rb`, `spec/forms/setup_form_spec.rb`

**Interfaces:**
- Consumes: `begin_two_factor(user)` (Task 3), `BusinessProvisioner.call` (Task 5), `User#accessible_businesses`, `#membership_for`, `#can_view_household?` (Task 4)
- Produces:
  - `ApplicationController#require_household` (prepended; redirects to `new_setup_path` when no household), `#require_household_owner!` (403), `#require_household_access!` (404)
  - `BusinessScoped` concern: sets `@business` from `params[:business_id]` via `Current.user.accessible_businesses` (404 otherwise) and `@membership`; `require_editor!`, `require_owner!` (403); helper `current_membership`
  - `SetupForm` (`household_name`, `name`, `email_address`, `password`, `password_confirmation`, `spouse_name`), `#save → User | nil`
  - Routes: `new_setup_path`, `setup_path`, `businesses_path`, `new_business_path`, `business_path(b)`, `edit_business_path(b)`
  - Helpers: `money(cents) → "$1.00"`, `business_nav(business)` renders `businesses/_nav`
  - `app/views/businesses/_nav.html.erb`: later tasks append one `<li>` link each

- [ ] **Step 1: Write the failing setup form spec**

`spec/forms/setup_form_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SetupForm do
  let(:attrs) do
    { household_name: "Our House", name: "Pat", email_address: "pat@example.com",
      password: AuthHelpers::PASSWORD, password_confirmation: AuthHelpers::PASSWORD, spouse_name: "Jordan" }
  end

  it "creates the household, the owner user, and both people" do
    user = SetupForm.new(attrs).save
    expect(user).to be_household_owner
    expect(Household.instance.name).to eq("Our House")
    expect(Household.instance.people.pluck(:name)).to contain_exactly("Pat", "Jordan")
    expect(user.person.name).to eq("Pat")
  end

  it "skips the spouse when blank" do
    SetupForm.new(attrs.merge(spouse_name: "")).save
    expect(Person.count).to eq(1)
  end

  it "returns nil with errors and creates nothing when invalid" do
    form = SetupForm.new(attrs.merge(password: "short", password_confirmation: "short"))
    expect(form.save).to be_nil
    expect(form.errors.full_messages.join).to match(/Password/)
    expect(Household.count).to eq(0)
    expect(User.count).to eq(0)
  end

  it "requires a household name" do
    form = SetupForm.new(attrs.merge(household_name: ""))
    expect(form.save).to be_nil
    expect(form.errors[:household_name]).to be_present
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/forms/setup_form_spec.rb`
Expected: FAIL with `uninitialized constant SetupForm`.

- [ ] **Step 3: Implement SetupForm**

`app/forms/setup_form.rb`:

```ruby
class SetupForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :household_name, :string
  attribute :name, :string
  attribute :email_address, :string
  attribute :password, :string
  attribute :password_confirmation, :string
  attribute :spouse_name, :string

  validates :household_name, :name, presence: true

  def save
    return unless valid?

    ApplicationRecord.transaction do
      household = Household.create!(name: household_name)
      user = User.create!(name:, email_address:, password:, password_confirmation:, household_owner: true)
      household.people.create!(name:, user:)
      household.people.create!(name: spouse_name) if spouse_name.present?
      user
    end
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.each { |error| errors.add(error.attribute, error.message) }
    nil
  end
end
```

Run: `bundle exec rspec spec/forms/setup_form_spec.rb`
Expected: PASS.

- [ ] **Step 4: Write the failing request specs**

`spec/requests/setup_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "First-run setup" do
  let(:params) do
    { setup: { household_name: "Our House", name: "Pat", email_address: "pat@example.com",
               password: AuthHelpers::PASSWORD, password_confirmation: AuthHelpers::PASSWORD, spouse_name: "Jordan" } }
  end

  it "redirects every page to setup until a household exists" do
    get root_path
    expect(response).to redirect_to(new_setup_path)
    get new_session_path
    expect(response).to redirect_to(new_setup_path)
  end

  it "creates the household and sends the owner to 2FA enrollment" do
    post setup_path, params: params
    expect(response).to redirect_to(new_two_factor_setup_path)
    expect(User.sole).to be_household_owner
  end

  it "re-renders with errors" do
    post setup_path, params: params.deep_merge(setup: { password: "short", password_confirmation: "short" })
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "is gone once a household exists" do
    create(:household)
    get new_setup_path
    expect(response).to have_http_status(:not_found)
    post setup_path, params: params
    expect(response).to have_http_status(:not_found)
  end
end
```

`spec/requests/businesses_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Businesses" do
  let!(:household) { create(:household) }
  let!(:person) { create(:person, household: household) }
  let(:household_owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, person: person, name: "Pat Consulting"), owner: household_owner) }

  describe "creating" do
    it "lets the household owner create a provisioned business" do
      sign_in_as household_owner
      post businesses_path, params: { business: { name: "Second Gig", person_id: person.id } }
      created = Business.find_by!(name: "Second Gig")
      expect(response).to redirect_to(business_path(created))
      expect(created.accounts.pluck(:name)).to eq(["Cash"])
      expect(household_owner.membership_for(created)).to be_owner
    end

    it "re-renders when invalid" do
      sign_in_as household_owner
      post businesses_path, params: { business: { name: "", person_id: person.id } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "forbids everyone else" do
      sign_in_as user_with_role("owner", business)
      get new_business_path
      expect(response).to have_http_status(:forbidden)
      post businesses_path, params: { business: { name: "Nope", person_id: person.id } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "showing" do
    it "shows a business to a viewer" do
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pat Consulting")
    end

    it "is not found for non-members" do
      sign_in_as create(:user)
      get business_path(business)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "editing" do
    it "lets a business owner rename" do
      owner = user_with_role("owner", business)
      sign_in_as owner
      patch business_path(business), params: { business: { name: "Renamed" } }
      expect(business.reload.name).to eq("Renamed")
    end

    it "forbids editors and viewers" do
      %w[editor viewer].each do |role|
        sign_in_as user_with_role(role, business)
        patch business_path(business), params: { business: { name: "Renamed" } }
        expect(response).to have_http_status(:forbidden)
        delete session_path
      end
    end
  end

  describe "dashboard" do
    it "lists only accessible businesses" do
      other = create(:business, name: "Hidden Biz")
      sign_in_as user_with_role("viewer", business)
      get root_path
      expect(response.body).to include("Pat Consulting")
      expect(response.body).not_to include("Hidden Biz")
      expect(other).to be_persisted
    end
  end
end
```

In `spec/requests/authentication_spec.rb`, add at the top of the `describe` block (setup redirects otherwise):

```ruby
  before { create(:household) }
```

- [ ] **Step 5: Run them to verify they fail**

Run: `bundle exec rspec spec/requests`
Expected: FAIL (no setup route, no businesses routes).

- [ ] **Step 6: Routes**

Add to `config/routes.rb` above `root`:

```ruby
  resource :setup, only: %i[new create]

  resources :businesses, only: %i[new create show edit update] do
  end
```

Later tasks add nested routes inside the `resources :businesses do ... end` block.

- [ ] **Step 7: ApplicationController and BusinessScoped**

`app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  include Authentication

  prepend_before_action :require_household

  allow_browser versions: :modern

  private

  def require_household
    redirect_to new_setup_path unless Household.exists?
  end

  def require_household_owner!
    head :forbidden unless Current.user.household_owner?
  end

  def require_household_access!
    head :not_found unless Current.user.can_view_household?
  end
end
```

(Keep any other lines the generator put there, such as `stale_when_importmap_changes`.)

`app/controllers/concerns/business_scoped.rb`:

```ruby
module BusinessScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_business
    helper_method :current_membership
  end

  private

  def set_business
    @business = Current.user.accessible_businesses.find(params[:business_id])
    @membership = Current.user.membership_for(@business)
  end

  def current_membership = @membership

  def require_editor!
    head :forbidden unless @membership.can_edit?
  end

  def require_owner!
    head :forbidden unless @membership.owner?
  end
end
```

- [ ] **Step 8: Controllers**

`app/controllers/setups_controller.rb`:

```ruby
class SetupsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_household
  before_action { head :not_found if Household.exists? }

  def new
    @setup = SetupForm.new
  end

  def create
    @setup = SetupForm.new(params.expect(setup: %i[household_name name email_address password password_confirmation spouse_name]))
    if (user = @setup.save)
      begin_two_factor(user)
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

`app/controllers/businesses_controller.rb`:

```ruby
class BusinessesController < ApplicationController
  before_action :require_household_owner!, only: %i[new create]
  before_action :set_business, only: %i[show edit update]
  before_action :require_owner!, only: %i[edit update]

  def new
    @business = Household.instance.businesses.new
  end

  def create
    @business = Household.instance.businesses.new(params.expect(business: %i[name person_id]))
    if @business.valid?
      BusinessProvisioner.call(@business, owner: Current.user)
      redirect_to business_path(@business), notice: "Business created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @accounts = @business.accounts.active.order(:name)
  end

  def edit
  end

  def update
    if @business.update(params.expect(business: %i[name]))
      redirect_to business_path(@business), notice: "Business updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_business
    @business = Current.user.accessible_businesses.find(params[:id])
    @membership = Current.user.membership_for(@business)
  end

  def require_owner!
    head :forbidden unless @membership.owner?
  end

  helper_method def current_membership = @membership
end
```

`app/controllers/dashboards_controller.rb`:

```ruby
class DashboardsController < ApplicationController
  def show
    @businesses = Current.user.accessible_businesses.active.order(:name)
  end
end
```

- [ ] **Step 9: Helpers, layout, views, styles**

`app/helpers/application_helper.rb`:

```ruby
module ApplicationHelper
  def money(cents)
    cents.nil? ? "—" : Money.new(cents).to_s
  end

  def business_nav(business)
    render "businesses/nav", business: business
  end
end
```

In `app/views/layouts/application.html.erb`, replace the `<nav class="site-nav">…</nav>` block with:

```erb
        <nav class="site-nav">
          <%= link_to "Businesses", root_path %>
          <%= button_to "Sign out", session_path, method: :delete %>
        </nav>
```

`app/views/setups/new.html.erb`:

```erb
<h1>Welcome to goodbooks</h1>
<p>Create your household and your login. You'll set up two-factor authentication next.</p>
<%= form_with model: @setup, scope: :setup, url: setup_path do |f| %>
  <%= render "shared/errors", record: @setup %>
  <p><%= f.label :household_name %> <%= f.text_field :household_name, required: true %></p>
  <p><%= f.label :name, "Your name" %> <%= f.text_field :name, required: true %></p>
  <p><%= f.label :email_address %> <%= f.email_field :email_address, required: true %></p>
  <p><%= f.label :password %> <%= f.password_field :password, required: true, minlength: 12 %></p>
  <p><%= f.label :password_confirmation %> <%= f.password_field :password_confirmation, required: true %></p>
  <p><%= f.label :spouse_name, "Spouse's name (optional)" %> <%= f.text_field :spouse_name %></p>
  <%= f.submit "Create household" %>
<% end %>
```

`app/views/shared/_errors.html.erb`:

```erb
<% if record.errors.any? %>
  <div class="errors">
    <ul>
      <% record.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  </div>
<% end %>
```

`app/views/dashboards/show.html.erb`:

```erb
<h1>Businesses</h1>
<ul class="business-list">
  <% @businesses.each do |business| %>
    <li><%= link_to business.name, business_path(business) %></li>
  <% end %>
</ul>
<% if Current.user.household_owner? %>
  <%= link_to "New business", new_business_path %>
<% end %>
```

`app/views/businesses/_nav.html.erb`:

```erb
<nav class="business-nav">
  <strong><%= business.name %></strong>
  <ul>
    <li><%= link_to "Overview", business_path(business) %></li>
  </ul>
</nav>
```

`app/views/businesses/_form.html.erb`:

```erb
<%= form_with model: business do |f| %>
  <%= render "shared/errors", record: business %>
  <p><%= f.label :name %> <%= f.text_field :name, required: true %></p>
  <% if business.new_record? %>
    <p>
      <%= f.label :person_id, "Owner (taxpayer)" %>
      <%= f.collection_select :person_id, Household.instance.people.order(:name), :id, :name %>
    </p>
  <% end %>
  <%= f.submit %>
<% end %>
```

`app/views/businesses/new.html.erb`:

```erb
<h1>New business</h1>
<%= render "form", business: @business %>
```

`app/views/businesses/edit.html.erb`:

```erb
<%= business_nav @business %>
<h1>Edit business</h1>
<%= render "form", business: @business %>
```

`app/views/businesses/show.html.erb`:

```erb
<%= business_nav @business %>
<h1><%= @business.name %></h1>
<p>Taxpayer: <%= @business.person.name %></p>
<h2>Accounts</h2>
<ul>
  <% @accounts.each do |account| %>
    <li><%= account.name %> (<%= account.source %>)</li>
  <% end %>
</ul>
<% if current_membership.owner? %>
  <%= link_to "Edit business", edit_business_path(@business) %>
<% end %>
```

Replace `app/assets/stylesheets/application.css` with:

```css
:root { --fg: #1d1d1f; --muted: #6e6e73; --line: #d2d2d7; --accent: #0b6e4f; --bad: #b00020; }
body { font-family: system-ui, sans-serif; color: var(--fg); margin: 0; }
main { max-width: 1100px; margin: 0 auto; padding: 1rem; }
.site-header { display: flex; justify-content: space-between; align-items: center; padding: .75rem 1rem; border-bottom: 1px solid var(--line); }
.site-nav { display: flex; gap: 1rem; align-items: center; }
.site-nav form { display: inline; }
.business-nav ul { display: flex; flex-wrap: wrap; gap: 1rem; list-style: none; padding: 0; }
.flash-alert, .errors { color: var(--bad); }
.flash-notice { color: var(--accent); }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: .35rem .5rem; border-bottom: 1px solid var(--line); }
td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
.inline-form { display: inline-flex; gap: .25rem; align-items: center; }
@media print { .no-print, .business-nav, .site-header { display: none; } }
```

- [ ] **Step 10: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "Add first-run setup, business screens, and business authorization concern"
```

---

### Task 7: Accounts management

**Files:**
- Create: `app/controllers/accounts_controller.rb`, `app/views/accounts/{index,new,edit,_form}.html.erb`
- Modify: `config/routes.rb`, `app/views/businesses/_nav.html.erb`
- Test: `spec/requests/accounts_spec.rb`

**Interfaces:**
- Consumes: `BusinessScoped` (Task 6), `Account` (Task 5)
- Produces: routes `business_accounts_path(b)`, `new_business_account_path(b)`, `edit_business_account_path(b, a)`. Owners create (source `manual` or `csv`), rename, change kind, archive (`archived: "1"`).

- [ ] **Step 1: Write the failing request spec**

`spec/requests/accounts_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Accounts" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business, name: "Checking") }

  it "lists accounts for viewers" do
    sign_in_as user_with_role("viewer", business)
    get business_accounts_path(business)
    expect(response.body).to include("Checking")
  end

  it "lets owners create a CSV account" do
    sign_in_as user_with_role("owner", business)
    post business_accounts_path(business), params: { account: { name: "Card", source: "csv", kind: "credit" } }
    expect(response).to redirect_to(business_accounts_path(business))
    expect(business.accounts.find_by!(name: "Card")).to be_csv
  end

  it "does not allow creating Plaid accounts by hand" do
    sign_in_as user_with_role("owner", business)
    post business_accounts_path(business), params: { account: { name: "Sneaky", source: "plaid", kind: "checking" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "lets owners archive" do
    sign_in_as user_with_role("owner", business)
    patch business_account_path(business, account), params: { account: { name: "Checking", kind: "checking", archived: "1" } }
    expect(account.reload).to be_archived
  end

  it "forbids editors and viewers from changing accounts" do
    %w[editor viewer].each do |role|
      sign_in_as user_with_role(role, business)
      post business_accounts_path(business), params: { account: { name: "X", source: "manual", kind: "cash" } }
      expect(response).to have_http_status(:forbidden)
      patch business_account_path(business, account), params: { account: { name: "Y" } }
      expect(response).to have_http_status(:forbidden)
      delete session_path
    end
  end

  it "is not found for non-members and for another business's account" do
    other_account = create(:account)
    sign_in_as user_with_role("owner", business)
    get edit_business_account_path(business, other_account)
    expect(response).to have_http_status(:not_found)
    delete session_path
    sign_in_as create(:user)
    get business_accounts_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/accounts_spec.rb`
Expected: FAIL (`undefined method 'business_accounts_path'`).

- [ ] **Step 3: Implement**

Inside `resources :businesses ... do` in `config/routes.rb`:

```ruby
    resources :accounts, only: %i[index new create edit update]
```

`app/controllers/accounts_controller.rb`:

```ruby
class AccountsController < ApplicationController
  include BusinessScoped

  CREATABLE_SOURCES = %w[manual csv].freeze

  before_action :require_owner!, except: :index
  before_action :set_account, only: %i[edit update]

  def index
    @accounts = @business.accounts.order(:archived_at, :name)
  end

  def new
    @account = @business.accounts.new(source: "manual", kind: "checking")
  end

  def create
    @account = @business.accounts.new(params.expect(account: %i[name source kind]))
    unless CREATABLE_SOURCES.include?(@account.source)
      @account.errors.add(:source, "must be manual or CSV")
      return render :new, status: :unprocessable_entity
    end

    if @account.save
      redirect_to business_accounts_path(@business), notice: "Account created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = params.expect(account: %i[name kind archived])
    archived = attrs.delete(:archived)
    @account.assign_attributes(attrs)
    @account.archived_at = archived == "1" ? (@account.archived_at || Time.current) : nil unless archived.nil?
    if @account.save
      redirect_to business_accounts_path(@business), notice: "Account updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_account
    @account = @business.accounts.find(params[:id])
  end
end
```

`app/views/accounts/index.html.erb`:

```erb
<%= business_nav @business %>
<h1>Accounts</h1>
<table>
  <thead><tr><th>Name</th><th>Source</th><th>Kind</th><th></th></tr></thead>
  <tbody>
    <% @accounts.each do |account| %>
      <tr id="<%= dom_id(account) %>">
        <td><%= account.name %><%= " (archived)" if account.archived? %></td>
        <td><%= account.source %></td>
        <td><%= account.kind %></td>
        <td><%= link_to "Edit", edit_business_account_path(@business, account) if current_membership.owner? %></td>
      </tr>
    <% end %>
  </tbody>
</table>
<%= link_to "New account", new_business_account_path(@business) if current_membership.owner? %>
```

`app/views/accounts/_form.html.erb`:

```erb
<%= form_with model: [@business, account] do |f| %>
  <%= render "shared/errors", record: account %>
  <p><%= f.label :name %> <%= f.text_field :name, required: true %></p>
  <% if account.new_record? %>
    <p><%= f.label :source %> <%= f.select :source, [["Manual entry", "manual"], ["CSV import", "csv"]] %></p>
  <% end %>
  <p><%= f.label :kind %> <%= f.select :kind, Account.kinds.keys.map { [_1.humanize, _1] } %></p>
  <% if account.persisted? %>
    <p><%= f.label :archived %> <%= f.check_box :archived, { checked: account.archived? }, "1", "0" %></p>
  <% end %>
  <%= f.submit %>
<% end %>
```

`app/views/accounts/new.html.erb`:

```erb
<%= business_nav @business %>
<h1>New account</h1>
<%= render "form", account: @account %>
```

`app/views/accounts/edit.html.erb`:

```erb
<%= business_nav @business %>
<h1>Edit account</h1>
<%= render "form", account: @account %>
```

`f.check_box :archived` needs a reader. Add to `app/models/account.rb`:

```ruby
  def archived = archived?
```

Append to the `<ul>` in `app/views/businesses/_nav.html.erb`:

```erb
    <li><%= link_to "Accounts", business_accounts_path(business) %></li>
```

- [ ] **Step 4: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add account management for business owners"
```

---

### Task 8: Categories management

**Files:**
- Create: `app/controllers/categories_controller.rb`, `app/views/categories/{index,new,edit,_form}.html.erb`
- Modify: `config/routes.rb`, `app/views/businesses/_nav.html.erb`
- Test: `spec/requests/categories_spec.rb`

**Interfaces:**
- Consumes: `Category`, `ScheduleC.options_for`, `#deductible_percent=` (Task 5)
- Produces: routes `business_categories_path(b)`, `new_business_category_path(b)`, `edit_business_category_path(b, c)`. Editors and owners add, rename, change the line or deductible %, and archive.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/categories_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Categories" do
  let!(:business) { create(:business) }
  let!(:category) { create(:category, business: business, name: "Office expense") }

  it "lists categories for viewers" do
    sign_in_as user_with_role("viewer", business)
    get business_categories_path(business)
    expect(response.body).to include("Office expense")
  end

  it "lets editors create with a deductible percent" do
    sign_in_as user_with_role("editor", business)
    post business_categories_path(business),
      params: { category: { name: "Client meals", kind: "expense", schedule_c_line: "24b", deductible_percent: "50" } }
    expect(response).to redirect_to(business_categories_path(business))
    expect(business.categories.find_by!(name: "Client meals").deductible_bps).to eq(5000)
  end

  it "re-renders on a line that doesn't match the kind" do
    sign_in_as user_with_role("editor", business)
    post business_categories_path(business), params: { category: { name: "Bad", kind: "income", schedule_c_line: "18", deductible_percent: "100" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "lets editors archive" do
    sign_in_as user_with_role("editor", business)
    patch business_category_path(business, category), params: { category: { archived: "1" } }
    expect(category.reload).to be_archived
  end

  it "forbids viewers from writing" do
    sign_in_as user_with_role("viewer", business)
    post business_categories_path(business), params: { category: { name: "X", kind: "expense", schedule_c_line: "18" } }
    expect(response).to have_http_status(:forbidden)
    patch business_category_path(business, category), params: { category: { name: "Y" } }
    expect(response).to have_http_status(:forbidden)
  end

  it "is not found for non-members" do
    sign_in_as create(:user)
    get business_categories_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/categories_spec.rb`
Expected: FAIL (`undefined method 'business_categories_path'`).

- [ ] **Step 3: Implement**

Routes, inside `resources :businesses do`:

```ruby
    resources :categories, only: %i[index new create edit update]
```

Add to `app/models/category.rb`:

```ruby
  def archived = archived?
```

`app/controllers/categories_controller.rb`:

```ruby
class CategoriesController < ApplicationController
  include BusinessScoped

  before_action :require_editor!, except: :index
  before_action :set_category, only: %i[edit update]

  def index
    @categories = @business.categories.order(:archived_at, :kind, :name)
  end

  def new
    @category = @business.categories.new(kind: "expense", schedule_c_line: "18")
  end

  def create
    @category = @business.categories.new(params.expect(category: %i[name kind schedule_c_line deductible_percent]))
    if @category.save
      redirect_to business_categories_path(@business), notice: "Category created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = params.expect(category: %i[name kind schedule_c_line deductible_percent archived])
    archived = attrs.delete(:archived)
    @category.assign_attributes(attrs)
    @category.archived_at = archived == "1" ? (@category.archived_at || Time.current) : nil unless archived.nil?
    if @category.save
      redirect_to business_categories_path(@business), notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_category
    @category = @business.categories.find(params[:id])
  end
end
```

`app/views/categories/index.html.erb`:

```erb
<%= business_nav @business %>
<h1>Categories</h1>
<table>
  <thead><tr><th>Name</th><th>Kind</th><th>Schedule C</th><th class="num">Deductible</th><th></th></tr></thead>
  <tbody>
    <% @categories.each do |category| %>
      <tr>
        <td><%= category.name %><%= " (archived)" if category.archived? %></td>
        <td><%= category.kind %></td>
        <td><%= ScheduleC.label(category.schedule_c_line) %></td>
        <td class="num"><%= category.deductible_percent %>%</td>
        <td><%= link_to "Edit", edit_business_category_path(@business, category) if current_membership.can_edit? %></td>
      </tr>
    <% end %>
  </tbody>
</table>
<%= link_to "New category", new_business_category_path(@business) if current_membership.can_edit? %>
```

`app/views/categories/_form.html.erb`:

```erb
<%= form_with model: [@business, category] do |f| %>
  <%= render "shared/errors", record: category %>
  <p><%= f.label :name %> <%= f.text_field :name, required: true %></p>
  <p><%= f.label :kind %> <%= f.select :kind, [["Income", "income"], ["Expense", "expense"]] %></p>
  <p>
    <%= f.label :schedule_c_line, "Schedule C line" %>
    <%= f.select :schedule_c_line, grouped_options_for_select(
          { "Income" => ScheduleC.options_for("income"), "Expense" => ScheduleC.options_for("expense") },
          category.schedule_c_line) %>
  </p>
  <p><%= f.label :deductible_percent, "Deductible %" %> <%= f.text_field :deductible_percent, size: 6 %></p>
  <% if category.persisted? %>
    <p><%= f.label :archived %> <%= f.check_box :archived, { checked: category.archived? }, "1", "0" %></p>
  <% end %>
  <%= f.submit %>
<% end %>
```

`app/views/categories/new.html.erb`:

```erb
<%= business_nav @business %>
<h1>New category</h1>
<%= render "form", category: @category %>
```

`app/views/categories/edit.html.erb`:

```erb
<%= business_nav @business %>
<h1>Edit category</h1>
<%= render "form", category: @category %>
```

Append to the nav `<ul>`:

```erb
    <li><%= link_to "Categories", business_categories_path(business) %></li>
```

- [ ] **Step 4: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add category management"
```

---

### Task 9: Transactions: model, manual entry, filtered list

**Files:**
- Create: migration `create_transactions`; `app/models/transaction.rb`; `app/models/transaction_filter.rb`; `app/controllers/transactions_controller.rb`; `app/views/transactions/{index,new,edit,_form}.html.erb`; `spec/factories/transactions.rb`
- Modify: `app/models/account.rb`, `app/models/business.rb`, `config/routes.rb`, `app/views/businesses/_nav.html.erb`, `app/views/accounts/index.html.erb`
- Test: `spec/models/transaction_spec.rb`, `spec/models/transaction_filter_spec.rb`, `spec/requests/transactions_spec.rb`

**Interfaces:**
- Consumes: `MoneyAttribute` (Task 2), `Account`, `Category` (Task 5)
- Produces:
  - `Transaction` columns: `account_id`, `posted_on:date`, `amount_cents:integer`, `payee`, `memo`, `category_id`, `transfer:boolean`, `excluded:boolean`, `external_id`, `categorized_by` (`"rule" | "user" | nil`), `rule_id:integer` (FK added in Task 11)
  - `Transaction#amount` / `#amount=` (money_attribute), `#direction=` (`"in"`/`"out"`, applied to the sign before validation), `#inbox?`, `#categorized_by_user?`, `#rule_attributes → { payee:, memo:, amount_cents: }`, `#business`
  - Scopes: `Transaction.inbox`, `.countable` (not transfer, not excluded), `.for_businesses(ids)`
  - `TransactionFilter.new(scope, params)` with `#results`, `#next_page?`, `#page`, `PER_PAGE = 50`; params `from`, `to` (ISO dates), `account_id`, `category_id`, `status` (`"inbox"`), `q`, `page`
  - `Account#transactions`, `Business#transactions` (through accounts)
  - Routes: `business_transactions_path(b, filters)`, `new_business_transaction_path(b)`, `edit_business_transaction_path(b, t)`, `business_transaction_path(b, t)`

- [ ] **Step 1: Migration**

```bash
bin/rails generate migration CreateTransactions
```

```ruby
class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :account, null: false, foreign_key: true
      t.date :posted_on, null: false
      t.integer :amount_cents, null: false
      t.string :payee, null: false
      t.string :memo
      t.references :category, foreign_key: true
      t.boolean :transfer, null: false, default: false
      t.boolean :excluded, null: false, default: false
      t.string :external_id
      t.string :categorized_by
      t.integer :rule_id
      t.timestamps
    end
    add_index :transactions, :posted_on
    add_index :transactions, :rule_id
    add_index :transactions, %i[account_id external_id], unique: true, where: "external_id IS NOT NULL"
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Factory**

`spec/factories/transactions.rb`:

```ruby
FactoryBot.define do
  factory :transaction do
    account
    posted_on { Date.new(2026, 1, 15) }
    amount_cents { -1000 }
    payee { "Office Depot" }
  end
end
```

- [ ] **Step 3: Write failing model specs**

`spec/models/transaction_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Transaction do
  let(:account) { create(:account) }

  it "parses the amount and applies the direction" do
    txn = Transaction.create!(account: account, posted_on: Date.current, payee: "Cash supplies", amount: "$12.50", direction: "out")
    expect(txn.amount_cents).to eq(-1250)
    txn.update!(amount: "-3", direction: "in")
    expect(txn.amount_cents).to eq(300)
  end

  it "reports a garbage amount instead of saving zero" do
    txn = Transaction.new(account: account, posted_on: Date.current, payee: "X", amount: "12a")
    expect(txn).not_to be_valid
    expect(txn.errors[:amount]).to include("is not a valid amount")
  end

  it "requires a category from the same business" do
    foreign = create(:category)
    txn = build(:transaction, account: account, category: foreign)
    expect(txn).not_to be_valid
    expect(txn.errors[:category]).to include("must belong to this business")
  end

  it "clears the category when marked as a transfer" do
    category = create(:category, business: account.business)
    txn = create(:transaction, account: account, category: category)
    txn.update!(transfer: true)
    expect(txn.category).to be_nil
  end

  describe "scopes" do
    let!(:inbox) { create(:transaction, account: account) }
    let!(:categorized) { create(:transaction, account: account, category: create(:category, business: account.business)) }
    let!(:transfer) { create(:transaction, account: account, transfer: true) }
    let!(:excluded) { create(:transaction, account: account, excluded: true) }

    it "inbox = uncategorized, not transfer, not excluded" do
      expect(Transaction.inbox).to contain_exactly(inbox)
      expect(inbox).to be_inbox
    end

    it "countable excludes transfers and excluded" do
      expect(Transaction.countable).to contain_exactly(inbox, categorized)
    end

    it "for_businesses filters by the account's business" do
      create(:transaction)
      expect(Transaction.for_businesses([account.business_id]).count).to eq(4)
    end
  end

  it "exposes the attributes rules match on" do
    txn = build(:transaction, payee: "ADOBE", memo: "CC", amount_cents: -5499)
    expect(txn.rule_attributes).to eq(payee: "ADOBE", memo: "CC", amount_cents: -5499)
  end
end
```

`spec/models/transaction_filter_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe TransactionFilter do
  let(:account) { create(:account) }
  let(:category) { create(:category, business: account.business) }
  let!(:jan) { create(:transaction, account: account, posted_on: Date.new(2026, 1, 1), payee: "Adobe", category: category) }
  let!(:dec) { create(:transaction, account: account, posted_on: Date.new(2026, 12, 31), payee: "Coffee", memo: "client mtg") }
  let(:scope) { Transaction.all }

  it "includes both ends of the date range" do
    results = TransactionFilter.new(scope, from: "2026-01-01", to: "2026-12-31").results
    expect(results).to contain_exactly(jan, dec)
  end

  it "ignores unparseable dates" do
    expect(TransactionFilter.new(scope, from: "garbage").results.count).to eq(2)
  end

  it "filters inbox, category, account, and text in payee or memo" do
    expect(TransactionFilter.new(scope, status: "inbox").results).to contain_exactly(dec)
    expect(TransactionFilter.new(scope, category_id: category.id.to_s).results).to contain_exactly(jan)
    expect(TransactionFilter.new(scope, q: "CLIENT").results).to contain_exactly(dec)
    expect(TransactionFilter.new(scope, q: "100%").results).to be_empty
    expect(TransactionFilter.new(scope, account_id: account.id.to_s).results.count).to eq(2)
  end

  it "orders newest first and paginates" do
    expect(TransactionFilter.new(scope, {}).results.first).to eq(dec)
    stub_const("TransactionFilter::PER_PAGE", 1)
    filter = TransactionFilter.new(scope, page: "1")
    expect(filter.results.to_a).to eq([dec])
    expect(filter.next_page?).to be(true)
    expect(TransactionFilter.new(scope, page: "2").next_page?).to be(false)
  end
end
```

- [ ] **Step 4: Run them to verify they fail**

Run: `bundle exec rspec spec/models/transaction_spec.rb spec/models/transaction_filter_spec.rb`
Expected: FAIL with `uninitialized constant Transaction`.

- [ ] **Step 5: Implement the model and filter**

`app/models/transaction.rb`:

```ruby
class Transaction < ApplicationRecord
  include MoneyAttribute

  CATEGORIZED_BY = %w[rule user].freeze

  money_attribute :amount
  attr_accessor :direction

  belongs_to :account
  belongs_to :category, optional: true

  scope :inbox, -> { where(category_id: nil, transfer: false, excluded: false) }
  scope :countable, -> { where(transfer: false, excluded: false) }
  scope :for_businesses, ->(ids) { joins(:account).where(accounts: { business_id: ids }) }

  validates :posted_on, :payee, presence: true
  validates :amount_cents, presence: true, numericality: { only_integer: true }
  validates :categorized_by, inclusion: { in: CATEGORIZED_BY }, allow_nil: true
  validate :category_in_business

  before_validation :apply_direction
  before_validation :clear_category_for_transfer

  delegate :business, to: :account

  def inbox? = category_id.nil? && !transfer? && !excluded?

  def categorized_by_user? = categorized_by == "user"

  def rule_attributes = { payee: payee, memo: memo, amount_cents: amount_cents }

  private

  def apply_direction
    return if direction.blank? || amount_cents.nil?

    self.amount_cents = direction == "out" ? -amount_cents.abs : amount_cents.abs
  end

  def clear_category_for_transfer
    self.category = nil if transfer?
  end

  def category_in_business
    return if category.nil? || account.nil?

    errors.add(:category, "must belong to this business") if category.business_id != account.business_id
  end
end
```

`app/models/transaction_filter.rb`:

```ruby
class TransactionFilter
  PER_PAGE = 50

  attr_reader :page

  def initialize(scope, params)
    @scope = scope
    @params = params.to_h.symbolize_keys
    @page = [@params[:page].to_i, 1].max
  end

  def results
    filtered.order(posted_on: :desc, id: :desc).limit(self.class::PER_PAGE).offset((page - 1) * self.class::PER_PAGE)
  end

  def next_page?
    filtered.count > page * self.class::PER_PAGE
  end

  def params = @params.slice(:from, :to, :account_id, :category_id, :status, :q)

  private

  def filtered
    relation = @scope
    relation = relation.where(posted_on: date(:from)..) if date(:from)
    relation = relation.where(posted_on: ..date(:to)) if date(:to)
    relation = relation.where(account_id: @params[:account_id]) if @params[:account_id].present?
    relation = relation.where(category_id: @params[:category_id]) if @params[:category_id].present?
    relation = relation.inbox if @params[:status] == "inbox"
    if @params[:q].present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@params[:q])}%"
      relation = relation.where("transactions.payee LIKE :p ESCAPE '\\' OR transactions.memo LIKE :p ESCAPE '\\'", p: pattern)
    end
    relation
  end

  def date(key)
    Date.iso8601(@params[key].to_s)
  rescue Date::Error
    nil
  end
end
```

Add to `app/models/account.rb`:

```ruby
  has_many :transactions, dependent: :restrict_with_error
```

Add to `app/models/business.rb`:

```ruby
  has_many :transactions, through: :accounts
```

- [ ] **Step 6: Run the model specs**

Run: `bundle exec rspec spec/models`
Expected: PASS.

- [ ] **Step 7: Write the failing request spec**

`spec/requests/transactions_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Transactions" do
  let!(:business) { create(:business) }
  let!(:cash) { create(:account, business: business, name: "Cash", source: "manual", kind: "cash") }
  let!(:bank) { create(:account, :csv, business: business, name: "Checking") }
  let!(:category) { create(:category, business: business, name: "Supplies", schedule_c_line: "22") }
  let!(:imported) { create(:transaction, account: bank, payee: "BANK PAYEE", amount_cents: -2000, external_id: "x1") }

  it "lists for viewers, filtered" do
    sign_in_as user_with_role("viewer", business)
    get business_transactions_path(business, q: "bank")
    expect(response.body).to include("BANK PAYEE")
  end

  it "lets editors add a manual cash expense" do
    sign_in_as user_with_role("editor", business)
    post business_transactions_path(business), params: { transaction: {
      account_id: cash.id, posted_on: "2026-02-03", payee: "Hardware store", amount: "$1,234.50", direction: "out", category_id: category.id
    } }
    expect(response).to redirect_to(business_transactions_path(business))
    txn = cash.transactions.sole
    expect(txn.amount_cents).to eq(-123450)
    expect(txn.categorized_by).to eq("user")
  end

  it "re-renders on a bad amount" do
    sign_in_as user_with_role("editor", business)
    post business_transactions_path(business), params: { transaction: {
      account_id: cash.id, posted_on: "2026-02-03", payee: "X", amount: "abc", direction: "out"
    } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("is not a valid amount")
  end

  it "does not add manual entries to imported accounts" do
    sign_in_as user_with_role("editor", business)
    post business_transactions_path(business), params: { transaction: {
      account_id: bank.id, posted_on: "2026-02-03", payee: "X", amount: "1", direction: "out"
    } }
    expect(response).to have_http_status(:not_found)
  end

  it "only lets imported transactions change category, transfer, memo, and excluded" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_path(business, imported), params: { transaction: {
      amount: "999", payee: "Changed", memo: "note", category_id: category.id
    } }
    imported.reload
    expect(imported.amount_cents).to eq(-2000)
    expect(imported.payee).to eq("BANK PAYEE")
    expect(imported.memo).to eq("note")
    expect(imported.category).to eq(category)
  end

  it "deletes manual transactions but not imported ones" do
    manual = create(:transaction, account: cash)
    sign_in_as user_with_role("editor", business)
    delete business_transaction_path(business, manual)
    expect(Transaction.exists?(manual.id)).to be(false)
    delete business_transaction_path(business, imported)
    expect(Transaction.exists?(imported.id)).to be(true)
  end

  it "forbids viewers from writing" do
    sign_in_as user_with_role("viewer", business)
    post business_transactions_path(business), params: { transaction: { account_id: cash.id, payee: "X", amount: "1" } }
    expect(response).to have_http_status(:forbidden)
    patch business_transaction_path(business, imported), params: { transaction: { memo: "x" } }
    expect(response).to have_http_status(:forbidden)
    delete business_transaction_path(business, imported)
    expect(response).to have_http_status(:forbidden)
  end

  it "is not found for another business's transaction" do
    sign_in_as user_with_role("editor", business)
    get edit_business_transaction_path(business, create(:transaction))
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 8: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/transactions_spec.rb`
Expected: FAIL (`undefined method 'business_transactions_path'`).

- [ ] **Step 9: Implement controller, routes, views**

Routes, inside `resources :businesses do`:

```ruby
    resources :transactions, except: :show
```

`app/controllers/transactions_controller.rb`:

```ruby
class TransactionsController < ApplicationController
  include BusinessScoped

  IMPORTED_EDITABLE = %i[memo category_id transfer excluded].freeze
  MANUAL_EDITABLE = %i[posted_on payee amount direction memo category_id transfer excluded].freeze

  before_action :require_editor!, except: :index
  before_action :set_transaction, only: %i[edit update destroy]

  def index
    @filter = TransactionFilter.new(Transaction.for_businesses(@business.id).includes(:account, :category), filter_params)
    @transactions = @filter.results
  end

  def new
    @transaction = Transaction.new(posted_on: Date.current, direction: "out")
  end

  def create
    attrs = params.expect(transaction: [:account_id, *MANUAL_EDITABLE])
    account = @business.accounts.manual.find(attrs.delete(:account_id))
    @transaction = account.transactions.new(attrs)
    @transaction.categorized_by = "user" if @transaction.category_id.present?
    if @transaction.save
      redirect_to business_transactions_path(@business), notice: "Transaction added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    permitted = @transaction.account.manual? ? MANUAL_EDITABLE : IMPORTED_EDITABLE
    attrs = params.expect(transaction: permitted)
    @transaction.assign_attributes(attrs)
    @transaction.categorized_by = "user" if attrs.key?(:category_id) || attrs.key?(:transfer)
    if @transaction.save
      redirect_to business_transactions_path(@business), notice: "Transaction updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @transaction.account.manual?
      @transaction.destroy!
      redirect_to business_transactions_path(@business), notice: "Transaction deleted.", status: :see_other
    else
      redirect_to business_transactions_path(@business), alert: "Imported transactions can be excluded, not deleted.", status: :see_other
    end
  end

  private

  def set_transaction
    @transaction = Transaction.for_businesses(@business.id).find(params[:id])
  end

  def filter_params
    params.permit(:from, :to, :account_id, :category_id, :status, :q, :page)
  end
end
```

`app/views/transactions/index.html.erb`:

```erb
<%= business_nav @business %>
<h1>Transactions</h1>
<%= form_with url: business_transactions_path(@business), method: :get, class: "inline-form no-print" do |f| %>
  <%= f.date_field :from, value: params[:from] %>
  <%= f.date_field :to, value: params[:to] %>
  <%= f.select :account_id, options_from_collection_for_select(@business.accounts.order(:name), :id, :name, params[:account_id]), include_blank: "All accounts" %>
  <%= f.select :category_id, options_from_collection_for_select(@business.categories.order(:name), :id, :name, params[:category_id]), include_blank: "All categories" %>
  <%= f.select :status, [["All", ""], ["Inbox only", "inbox"]], selected: params[:status] %>
  <%= f.search_field :q, value: params[:q], placeholder: "Search payee or memo" %>
  <%= f.submit "Filter" %>
<% end %>
<table>
  <thead><tr><th>Date</th><th>Account</th><th>Payee</th><th>Memo</th><th>Category</th><th class="num">Amount</th><th></th></tr></thead>
  <tbody>
    <% @transactions.each do |txn| %>
      <tr id="<%= dom_id(txn) %>">
        <td><%= txn.posted_on %></td>
        <td><%= txn.account.name %></td>
        <td><%= txn.payee %></td>
        <td><%= txn.memo %></td>
        <td><%= txn.transfer? ? "Transfer" : txn.excluded? ? "Excluded" : txn.category&.name || "Inbox" %></td>
        <td class="num"><%= money(txn.amount_cents) %></td>
        <td><%= link_to "Edit", edit_business_transaction_path(@business, txn) if current_membership.can_edit? %></td>
      </tr>
    <% end %>
  </tbody>
</table>
<p>
  <%= link_to "Previous", business_transactions_path(@business, @filter.params.merge(page: @filter.page - 1)) if @filter.page > 1 %>
  <%= link_to "Next", business_transactions_path(@business, @filter.params.merge(page: @filter.page + 1)) if @filter.next_page? %>
</p>
<%= link_to "Add manual transaction", new_business_transaction_path(@business) if current_membership.can_edit? %>
```

`app/views/transactions/_form.html.erb`:

```erb
<%= form_with model: [@business, transaction] do |f| %>
  <%= render "shared/errors", record: transaction %>
  <% manual = transaction.new_record? || transaction.account.manual? %>
  <% if transaction.new_record? %>
    <p><%= f.label :account_id %> <%= f.collection_select :account_id, @business.accounts.manual.active.order(:name), :id, :name %></p>
  <% end %>
  <% if manual %>
    <p><%= f.label :posted_on, "Date" %> <%= f.date_field :posted_on, required: true %></p>
    <p><%= f.label :payee %> <%= f.text_field :payee, required: true %></p>
    <p>
      <%= f.label :amount %>
      <%= f.text_field :amount, value: transaction.amount_cents ? Money.new(transaction.amount_cents.abs).to_input : transaction.amount %>
      <% out = transaction.direction.present? ? transaction.direction == "out" : transaction.amount_cents.to_i <= 0 %>
      <label><%= f.radio_button :direction, "out", checked: out %> Money out</label>
      <label><%= f.radio_button :direction, "in", checked: !out %> Money in</label>
    </p>
  <% else %>
    <p><%= transaction.posted_on %> · <%= transaction.payee %> · <%= money(transaction.amount_cents) %> (imported, read-only)</p>
  <% end %>
  <p><%= f.label :memo %> <%= f.text_field :memo %></p>
  <p>
    <%= f.label :category_id %>
    <%= f.grouped_collection_select :category_id,
          [["Income", @business.categories.active.income.order(:name)], ["Expense", @business.categories.active.expense.order(:name)]],
          :last, :first, :id, :name, include_blank: "Uncategorized" %>
  </p>
  <p><%= f.label :transfer %> <%= f.check_box :transfer %></p>
  <p><%= f.label :excluded %> <%= f.check_box :excluded %></p>
  <%= f.submit %>
<% end %>
<% if transaction.persisted? && transaction.account.manual? %>
  <%= button_to "Delete", business_transaction_path(@business, transaction), method: :delete %>
<% end %>
```

`app/views/transactions/new.html.erb`:

```erb
<%= business_nav @business %>
<h1>Add manual transaction</h1>
<%= render "form", transaction: @transaction %>
```

`app/views/transactions/edit.html.erb`:

```erb
<%= business_nav @business %>
<h1>Edit transaction</h1>
<%= render "form", transaction: @transaction %>
```

In `app/views/accounts/index.html.erb`, change the account name cell to link to its transactions:

```erb
        <td><%= link_to account.name, business_transactions_path(@business, account_id: account.id) %><%= " (archived)" if account.archived? %></td>
```

Append to the nav `<ul>`:

```erb
    <li><%= link_to "Transactions", business_transactions_path(business) %></li>
```

- [ ] **Step 10: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "Add transactions with manual entry and filtered listing"
```

---

### Task 10: RuleEngine (pure matching)

**Files:**
- Create: `app/models/rule_engine.rb`
- Test: `spec/models/rule_engine_spec.rb`

**Interfaces:**
- Produces: `RuleEngine.match(attrs, rules) → rule | nil`, where `attrs` is `{ payee:, memo:, amount_cents: }` and each rule responds to `field` (`"payee"|"memo"`), `operator` (`"contains"|"equals"|"starts_with"`), `value`, `amount_min_cents`, `amount_max_cents`. `rules` must already be in priority order; the first match wins. Matching is case-insensitive and whitespace-normalized. Amount bounds are inclusive and compare against `amount_cents.abs`.

- [ ] **Step 1: Write the failing spec**

`spec/models/rule_engine_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe RuleEngine do
  FakeRule = Struct.new(:name, :field, :operator, :value, :amount_min_cents, :amount_max_cents, keyword_init: true)

  def rule(name, field: "payee", operator: "contains", value:, min: nil, max: nil)
    FakeRule.new(name:, field:, operator:, value:, amount_min_cents: min, amount_max_cents: max)
  end

  let(:attrs) { { payee: "  ADOBE   Creative Cloud ", memo: "Monthly SUB", amount_cents: -5499 } }

  it "matches contains, case-insensitively, with normalized whitespace" do
    expect(RuleEngine.match(attrs, [rule("a", value: "adobe creative")])&.name).to eq("a")
  end

  it "matches equals against the whole normalized value" do
    expect(RuleEngine.match(attrs, [rule("a", operator: "equals", value: "adobe creative cloud")])&.name).to eq("a")
    expect(RuleEngine.match(attrs, [rule("a", operator: "equals", value: "adobe")])).to be_nil
  end

  it "matches starts_with" do
    expect(RuleEngine.match(attrs, [rule("a", operator: "starts_with", value: "ADOBE")])&.name).to eq("a")
    expect(RuleEngine.match(attrs, [rule("a", operator: "starts_with", value: "cloud")])).to be_nil
  end

  it "matches on memo" do
    expect(RuleEngine.match(attrs, [rule("a", field: "memo", value: "monthly")])&.name).to eq("a")
  end

  it "treats a nil memo as empty" do
    expect(RuleEngine.match(attrs.merge(memo: nil), [rule("a", field: "memo", value: "x")])).to be_nil
  end

  it "applies inclusive absolute amount bounds" do
    expect(RuleEngine.match(attrs, [rule("a", value: "adobe", min: 5499, max: 5499)])&.name).to eq("a")
    expect(RuleEngine.match(attrs, [rule("a", value: "adobe", min: 5500)])).to be_nil
    expect(RuleEngine.match(attrs, [rule("a", value: "adobe", max: 5000)])).to be_nil
  end

  it "returns the first match in order" do
    rules = [rule("first", value: "creative"), rule("second", value: "adobe")]
    expect(RuleEngine.match(attrs, rules).name).to eq("first")
  end

  it "returns nil when nothing matches" do
    expect(RuleEngine.match(attrs, [rule("a", value: "google")])).to be_nil
    expect(RuleEngine.match(attrs, [])).to be_nil
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/models/rule_engine_spec.rb`
Expected: FAIL with `uninitialized constant RuleEngine`.

- [ ] **Step 3: Implement**

`app/models/rule_engine.rb`:

```ruby
module RuleEngine
  module_function

  def match(attrs, rules)
    rules.find { |rule| matches?(rule, attrs) }
  end

  def matches?(rule, attrs)
    text_matches?(rule, normalize(attrs[rule.field.to_sym])) && amount_matches?(rule, attrs[:amount_cents].to_i.abs)
  end

  def text_matches?(rule, text)
    value = normalize(rule.value)
    case rule.operator
    when "contains" then text.include?(value)
    when "equals" then text == value
    when "starts_with" then text.start_with?(value)
    else false
    end
  end

  def amount_matches?(rule, cents)
    (rule.amount_min_cents.nil? || cents >= rule.amount_min_cents) &&
      (rule.amount_max_cents.nil? || cents <= rule.amount_max_cents)
  end

  def normalize(text) = text.to_s.downcase.squish
end
```

- [ ] **Step 4: Run it**

Run: `bundle exec rspec spec/models/rule_engine_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add pure rule matching engine"
```

---

### Task 11: Rules management and RuleApplier

**Files:**
- Create: migration `create_rules`; `app/models/rule.rb`; `app/services/rule_applier.rb`; `app/controllers/rules_controller.rb`; `app/views/rules/{index,new,edit,_form}.html.erb`; `app/javascript/controllers/sortable_controller.js`; `spec/factories/rules.rb`; `spec/support/capybara.rb`
- Modify: `Gemfile` (selenium-webdriver), `config/importmap.rb` (sortablejs), `spec/rails_helper.rb` (JS driver), `app/models/transaction.rb`, `app/models/business.rb`, `config/routes.rb`, `app/views/businesses/_nav.html.erb`, `app/assets/stylesheets/application.css`
- Test: `spec/models/rule_spec.rb`, `spec/services/rule_applier_spec.rb`, `spec/requests/rules_spec.rb`, `spec/system/rule_reorder_spec.rb`

**Interfaces:**
- Consumes: `RuleEngine.match` (Task 10), `Transaction#inbox?`, `#categorized_by_user?`, `#rule_attributes` (Task 9)
- Produces:
  - `Rule` (`business`, `position`, `field`, `operator`, `value`, `amount_min_cents`, `amount_max_cents`, `outcome` in `categorize|transfer`, `category`), `money_attribute :amount_min/:amount_max, allow_blank: true`, `Rule.ordered`, `#move_to!(position)` (1-based, clamped, renumbers all rules 1..n), `#description → String`
  - `Transaction#rule` (belongs_to, optional)
  - `RuleApplier.new(business).apply(transactions) → Integer` (count changed). It only touches transactions that are `inbox?` and not `categorized_by_user?`, and sets `category` or `transfer`, `categorized_by: "rule"`, and `rule`.
  - Routes: `business_rules_path`, `new_business_rule_path(b, value:, category_id:)`, `edit_business_rule_path`, `move_business_rule_path(b, r)` (PATCH, param `position`, responds 204), `apply_business_rules_path(b)`
  - Stimulus `sortable` controller: attach to a `<tbody>`; rows carry `data-sortable-url`; drag via `.drag-handle`; sets `data-sortable-state` on the tbody to `saving` / `saved` / `error`

- [ ] **Step 1: Migration**

```bash
bin/rails generate migration CreateRules
```

```ruby
class CreateRules < ActiveRecord::Migration[8.1]
  def change
    create_table :rules do |t|
      t.references :business, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :field, null: false
      t.string :operator, null: false
      t.string :value, null: false
      t.integer :amount_min_cents
      t.integer :amount_max_cents
      t.string :outcome, null: false
      t.references :category, foreign_key: true
      t.timestamps
    end
    add_foreign_key :transactions, :rules, on_delete: :nullify
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Factory**

`spec/factories/rules.rb`:

```ruby
FactoryBot.define do
  factory :rule do
    business
    field { "payee" }
    operator { "contains" }
    value { "adobe" }
    outcome { "categorize" }
    category { association :category, business: business }
  end
end
```

- [ ] **Step 3: Write failing specs**

`spec/models/rule_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Rule do
  let(:business) { create(:business) }

  it "assigns increasing positions" do
    first = create(:rule, business: business)
    second = create(:rule, business: business)
    expect([first.position, second.position]).to eq([1, 2])
  end

  it "requires a category to categorize, from the same business" do
    expect(build(:rule, business: business, category: nil)).not_to be_valid
    expect(build(:rule, business: business, category: create(:category))).not_to be_valid
    expect(build(:rule, business: business, outcome: "transfer", category: nil)).to be_valid
  end

  it "rejects unknown fields, operators, and outcomes" do
    expect(build(:rule, field: "amount")).not_to be_valid
    expect(build(:rule, operator: "regex")).not_to be_valid
    expect(build(:rule, outcome: "delete")).not_to be_valid
  end

  it "parses optional amount bounds and rejects negatives" do
    rule = build(:rule, business: business, amount_min: "", amount_max: "$100")
    expect(rule.amount_min_cents).to be_nil
    expect(rule.amount_max_cents).to eq(10000)
    expect(build(:rule, business: business, amount_min: "-5")).not_to be_valid
  end

  it "moves to a position and renumbers the rest" do
    a, b, c = Array.new(3) { create(:rule, business: business) }
    c.move_to!(1)
    expect(business.rules.ordered).to eq([c, a, b])
    expect(business.rules.ordered.pluck(:position)).to eq([1, 2, 3])
    c.move_to!(99)
    expect(business.rules.ordered).to eq([a, b, c])
    b.move_to!(0)
    expect(business.rules.ordered).to eq([b, a, c])
  end

  it "does not touch another business's rules" do
    other = create(:rule)
    mine = create(:rule, business: business)
    mine.move_to!(1)
    expect(other.reload.position).to eq(1)
  end
end
```

`spec/services/rule_applier_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe RuleApplier do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }
  let(:software) { create(:category, business: business, name: "Software") }
  let!(:rule) { create(:rule, business: business, value: "adobe", category: software) }
  let!(:transfer_rule) { create(:rule, business: business, value: "card payment", outcome: "transfer", category: nil) }

  it "categorizes matching inbox transactions and records the rule" do
    txn = create(:transaction, account: account, payee: "ADOBE *CC")
    expect(RuleApplier.new(business).apply([txn])).to eq(1)
    txn.reload
    expect(txn.category).to eq(software)
    expect(txn.categorized_by).to eq("rule")
    expect(txn.rule).to eq(rule)
  end

  it "marks transfers" do
    txn = create(:transaction, account: account, payee: "Card payment thank you")
    RuleApplier.new(business).apply([txn])
    expect(txn.reload).to be_transfer
  end

  it "never overrides a user's choice, even an uncategorized one" do
    other = create(:category, business: business, name: "Other")
    chosen = create(:transaction, account: account, payee: "ADOBE", category: other, categorized_by: "user")
    cleared = create(:transaction, account: account, payee: "ADOBE", categorized_by: "user")
    expect(RuleApplier.new(business).apply([chosen, cleared])).to eq(0)
    expect(chosen.reload.category).to eq(other)
    expect(cleared.reload.category).to be_nil
  end

  it "leaves non-matching transactions alone" do
    txn = create(:transaction, account: account, payee: "Coffee")
    expect(RuleApplier.new(business).apply([txn])).to eq(0)
    expect(txn.reload).to be_inbox
  end

  it "nullifies the transaction's rule when the rule is deleted" do
    txn = create(:transaction, account: account, payee: "ADOBE")
    RuleApplier.new(business).apply([txn])
    rule.destroy!
    expect(txn.reload.rule_id).to be_nil
    expect(txn.category).to eq(software)
  end
end
```

`spec/requests/rules_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Rules" do
  let!(:business) { create(:business) }
  let!(:category) { create(:category, business: business, name: "Software") }

  it "lets editors create a rule" do
    sign_in_as user_with_role("editor", business)
    post business_rules_path(business), params: { rule: {
      field: "payee", operator: "contains", value: "adobe", outcome: "categorize", category_id: category.id, amount_min: "", amount_max: ""
    } }
    expect(response).to redirect_to(business_rules_path(business))
    expect(business.rules.sole.value).to eq("adobe")
  end

  it "prefills the new form from params" do
    sign_in_as user_with_role("editor", business)
    get new_business_rule_path(business, value: "ADOBE", category_id: category.id)
    expect(response.body).to include('value="ADOBE"')
  end

  it "reorders from a JSON position" do
    a = create(:rule, business: business, category: category)
    b = create(:rule, business: business, category: category)
    sign_in_as user_with_role("editor", business)
    patch move_business_rule_path(business, b), params: { position: 1 }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(business.rules.ordered.to_a).to eq([b, a])
  end

  it "rejects a move without a position" do
    rule = create(:rule, business: business, category: category)
    sign_in_as user_with_role("editor", business)
    patch move_business_rule_path(business, rule), params: {}, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "applies rules to the inbox" do
    create(:rule, business: business, value: "adobe", category: category)
    txn = create(:transaction, account: create(:account, business: business), payee: "Adobe")
    sign_in_as user_with_role("editor", business)
    post apply_business_rules_path(business)
    expect(txn.reload.category).to eq(category)
    expect(flash[:notice]).to eq("1 transaction categorized.")
  end

  it "forbids viewers from writing" do
    rule = create(:rule, business: business, category: category)
    sign_in_as user_with_role("viewer", business)
    post business_rules_path(business), params: { rule: { value: "x" } }
    expect(response).to have_http_status(:forbidden)
    patch move_business_rule_path(business, rule), params: { position: 1 }, as: :json
    expect(response).to have_http_status(:forbidden)
    post apply_business_rules_path(business)
    expect(response).to have_http_status(:forbidden)
    delete business_rule_path(business, rule)
    expect(response).to have_http_status(:forbidden)
  end
end
```

- [ ] **Step 4: Run them to verify they fail**

Run: `bundle exec rspec spec/models/rule_spec.rb spec/services/rule_applier_spec.rb spec/requests/rules_spec.rb`
Expected: FAIL with `uninitialized constant Rule`.

- [ ] **Step 5: Implement model and service**

`app/models/rule.rb`:

```ruby
class Rule < ApplicationRecord
  include MoneyAttribute

  FIELDS = %w[payee memo].freeze
  OPERATORS = %w[contains equals starts_with].freeze
  OUTCOMES = %w[categorize transfer].freeze

  money_attribute :amount_min, allow_blank: true
  money_attribute :amount_max, allow_blank: true

  belongs_to :business
  belongs_to :category, optional: true
  has_many :transactions, dependent: :nullify

  scope :ordered, -> { order(:position) }

  validates :field, inclusion: { in: FIELDS }
  validates :operator, inclusion: { in: OPERATORS }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :value, presence: true
  validates :category, presence: true, if: -> { outcome == "categorize" }
  validates :amount_min_cents, :amount_max_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :category_in_business

  before_validation { self.category = nil if outcome == "transfer" }
  before_create { self.position = (business.rules.maximum(:position) || 0) + 1 }

  def move_to!(new_position)
    ApplicationRecord.transaction do
      ids = business.rules.ordered.where.not(id: id).pluck(:id)
      ids.insert(new_position.to_i.clamp(1, ids.size + 1) - 1, id)
      ids.each.with_index(1) { |rule_id, position| Rule.where(id: rule_id).update_all(position: position) }
    end
    reload
  end

  def description
    target = outcome == "transfer" ? "Transfer" : category&.name
    "#{field} #{operator.humanize(capitalize: false)} \"#{value}\" → #{target}"
  end

  private

  def category_in_business
    errors.add(:category, "must belong to this business") if category && category.business_id != business_id
  end
end
```

Add to `app/models/transaction.rb`:

```ruby
  belongs_to :rule, optional: true
```

Add to `app/models/business.rb`:

```ruby
  has_many :rules, dependent: :destroy
```

`app/services/rule_applier.rb`:

```ruby
class RuleApplier
  def initialize(business)
    @rules = business.rules.ordered.includes(:category).to_a
  end

  def apply(transactions)
    transactions.count do |txn|
      next false unless txn.inbox? && !txn.categorized_by_user?

      rule = RuleEngine.match(txn.rule_attributes, @rules)
      next false unless rule

      txn.update!(
        rule: rule,
        categorized_by: "rule",
        transfer: rule.outcome == "transfer",
        category: rule.outcome == "categorize" ? rule.category : nil
      )
      true
    end
  end
end
```

- [ ] **Step 6: Controller, routes, views**

Routes, inside `resources :businesses do`:

```ruby
    resources :rules, except: :show do
      patch :move, on: :member
      post :apply, on: :collection
    end
```

`app/controllers/rules_controller.rb`:

```ruby
class RulesController < ApplicationController
  include BusinessScoped

  PERMITTED = %i[field operator value amount_min amount_max outcome category_id].freeze

  before_action :require_editor!, except: :index
  before_action :set_rule, only: %i[edit update destroy move]

  def index
    @rules = @business.rules.ordered.includes(:category)
  end

  def new
    @rule = @business.rules.new(field: "payee", operator: "contains", outcome: "categorize",
                                value: params[:value], category_id: params[:category_id])
  end

  def create
    @rule = @business.rules.new(params.expect(rule: PERMITTED))
    if @rule.save
      redirect_to business_rules_path(@business), notice: "Rule created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @rule.update(params.expect(rule: PERMITTED))
      redirect_to business_rules_path(@business), notice: "Rule updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy!
    redirect_to business_rules_path(@business), notice: "Rule deleted.", status: :see_other
  end

  def move
    @rule.move_to!(params.expect(:position))
    head :no_content
  end

  def apply
    count = RuleApplier.new(@business).apply(@business.transactions.inbox.to_a)
    redirect_to business_inbox_path(@business), notice: "#{count} #{"transaction".pluralize(count)} categorized.", status: :see_other
  end

  private

  def set_rule
    @rule = @business.rules.find(params[:id])
  end
end
```

`apply` redirects to `business_inbox_path`, so add the inbox route now, inside `resources :businesses do`:

```ruby
    resource :inbox, only: :show
```

and create a placeholder `app/controllers/inboxes_controller.rb` that Task 12 replaces:

```ruby
class InboxesController < ApplicationController
  include BusinessScoped

  def show
    head :ok
  end
end
```

`app/views/rules/index.html.erb`:

```erb
<%= business_nav @business %>
<h1>Rules</h1>
<p>Rules run top to bottom on new imported transactions. The first match wins.<%= " Drag ≡ to reorder." if current_membership.can_edit? %></p>
<table>
  <thead><tr><th></th><th>Rule</th><th>Amount</th><th></th></tr></thead>
  <tbody <%= tag.attributes(data: { controller: "sortable" }) if current_membership.can_edit? %>>
    <% @rules.each do |rule| %>
      <tr id="<%= dom_id(rule) %>" data-sortable-url="<%= move_business_rule_path(@business, rule) %>">
        <td><% if current_membership.can_edit? %><span class="drag-handle" title="Drag to reorder">≡</span><% end %></td>
        <td><%= rule.description %></td>
        <td><%= [rule.amount_min_cents && "≥ #{money(rule.amount_min_cents)}", rule.amount_max_cents && "≤ #{money(rule.amount_max_cents)}"].compact.join(" ") %></td>
        <td>
          <% if current_membership.can_edit? %>
            <%= link_to "Edit", edit_business_rule_path(@business, rule) %>
            <%= button_to "Delete", business_rule_path(@business, rule), method: :delete, form_class: "inline-form" %>
          <% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
<%= link_to "New rule", new_business_rule_path(@business) if current_membership.can_edit? %>
```

`app/views/rules/_form.html.erb`:

```erb
<%= form_with model: [@business, rule] do |f| %>
  <%= render "shared/errors", record: rule %>
  <p>
    When
    <%= f.select :field, Rule::FIELDS.map { [_1.humanize, _1] } %>
    <%= f.select :operator, Rule::OPERATORS.map { [_1.humanize(capitalize: false), _1] } %>
    <%= f.text_field :value, required: true %>
  </p>
  <p>
    and amount between <%= f.text_field :amount_min, size: 8, placeholder: "any" %>
    and <%= f.text_field :amount_max, size: 8, placeholder: "any" %> (absolute value)
  </p>
  <p>
    then <%= f.select :outcome, [["categorize as", "categorize"], ["mark as transfer", "transfer"]] %>
    <%= f.grouped_collection_select :category_id,
          [["Income", @business.categories.active.income.order(:name)], ["Expense", @business.categories.active.expense.order(:name)]],
          :last, :first, :id, :name, include_blank: "—" %>
  </p>
  <%= f.submit %>
<% end %>
```

`app/views/rules/new.html.erb`:

```erb
<%= business_nav @business %>
<h1>New rule</h1>
<%= render "form", rule: @rule %>
```

`app/views/rules/edit.html.erb`:

```erb
<%= business_nav @business %>
<h1>Edit rule</h1>
<%= render "form", rule: @rule %>
```

Append to the nav `<ul>`:

```erb
    <li><%= link_to "Rules", business_rules_path(business) %></li>
```

Append to `app/assets/stylesheets/application.css`:

```css
.drag-handle { cursor: grab; user-select: none; padding: 0 .5rem; font-size: 1.2rem; }
.sortable-ghost { opacity: .4; }
```

- [ ] **Step 7: Drag-and-drop: write the failing JS system spec**

Add to the `:test` group in `Gemfile` and install:

```ruby
  gem "selenium-webdriver", "~> 4.27"
```

```bash
bundle install
```

`spec/support/capybara.rb`:

```ruby
Capybara.server = :puma, { Silent: true }
Selenium::WebDriver.logger.level = :error
```

In `spec/rails_helper.rb`, replace `config.before(:each, type: :system) { driven_by :rack_test }` with:

```ruby
  config.before(:each, type: :system) do |example|
    if example.metadata[:js]
      driven_by :selenium, using: :headless_chrome, screen_size: [1400, 900]
    else
      driven_by :rack_test
    end
  end
```

`spec/system/rule_reorder_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Reordering rules", js: true do
  let!(:business) { create(:business) }
  let!(:category) { create(:category, business: business, name: "Software") }
  let!(:first_rule) { create(:rule, business: business, value: "alpha", category: category) }
  let!(:second_rule) { create(:rule, business: business, value: "bravo", category: category) }

  it "saves the new order after dragging a rule to the top" do
    system_sign_in_as user_with_role("editor", business)
    visit business_rules_path(business)
    find("#rule_#{second_rule.id} .drag-handle").drag_to(find("#rule_#{first_rule.id}"))
    expect(page).to have_css("tbody[data-sortable-state='saved']")
    expect(page).to have_css("tbody tr:first-child#rule_#{second_rule.id}")
    expect(business.rules.ordered.to_a).to eq([second_rule, first_rule])
  end

  it "shows no drag handles to viewers" do
    system_sign_in_as user_with_role("viewer", business)
    visit business_rules_path(business)
    expect(page).to have_content("alpha")
    expect(page).to have_no_css(".drag-handle")
  end
end
```

Run: `bundle exec rspec spec/system/rule_reorder_spec.rb`
Expected: the first example FAILS (no `data-sortable-state`; the controller doesn't exist yet). Selenium Manager downloads chromedriver on first run; Chrome is installed at `/Applications/Google Chrome.app`.

- [ ] **Step 8: Drag-and-drop: implement the Stimulus controller**

```bash
bin/importmap pin sortablejs
```

`app/javascript/controllers/sortable_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag rows (by .drag-handle) to reorder. PATCHes the moved row's data-sortable-url
// with its new 1-based position and reports progress in data-sortable-state.
export default class extends Controller {
  connect() {
    this.sortable = Sortable.create(this.element, {
      handle: ".drag-handle",
      forceFallback: true,
      onEnd: (event) => this.save(event)
    })
  }

  disconnect() {
    this.sortable.destroy()
  }

  async save({ item, newIndex, oldIndex }) {
    if (newIndex === oldIndex) return

    this.element.dataset.sortableState = "saving"
    const response = await fetch(item.dataset.sortableUrl, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify({ position: newIndex + 1 })
    })
    this.element.dataset.sortableState = response.ok ? "saved" : "error"
  }
}
```

`forceFallback: true` makes Sortable use mouse events instead of native HTML5 drag-and-drop. Selenium's `drag_to` drives the mouse, so this is what makes the behavior testable (and it behaves the same for users). Stimulus auto-registers the controller through `eagerLoadControllersFrom("controllers", ...)` in `app/javascript/controllers/index.js`.

If `drag_to` doesn't trigger Sortable reliably, replace it in the spec with explicit stepped mouse moves:

```ruby
    handle = find("#rule_#{second_rule.id} .drag-handle").native
    target = find("#rule_#{first_rule.id}").native
    page.driver.browser.action.click_and_hold(handle).move_to(target, 0, -5).pause(duration: 0.2).move_to(target, 0, -10).release.perform
```

Run: `bundle exec rspec spec/system/rule_reorder_spec.rb`
Expected: PASS, with no Puma, Selenium, or browser console output.

- [ ] **Step 9: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "Add categorization rules with drag-and-drop ordering and rule applier"
```

---

### Task 12: Categorization inbox (business and household)

**Files:**
- Create: `app/controllers/classifications_controller.rb`, `app/controllers/household_inboxes_controller.rb`, `app/views/inboxes/show.html.erb`, `app/views/inboxes/_row.html.erb`, `app/views/household_inboxes/show.html.erb`
- Modify: `app/controllers/inboxes_controller.rb` (replace the placeholder), `config/routes.rb`, `app/views/businesses/_nav.html.erb`, `app/views/layouts/application.html.erb`
- Test: `spec/requests/inbox_spec.rb`

**Interfaces:**
- Consumes: `Transaction.inbox`, `.for_businesses`, `RuleApplier` (Tasks 9, 11)
- Produces:
  - Routes: `business_inbox_path(b)`, `business_transaction_classification_path(b, t)` (PATCH), `household_inbox_path`
  - `ClassificationsController#update`, with params `outcome` (`categorize|transfer|exclude`), `category_id`, `make_rule` (`"1"`). Responds with a turbo_stream `remove` of `dom_id(txn)`, or redirects back (HTML). With `make_rule=1` and a category, it redirects to `new_business_rule_path(b, value: <first payee word>, category_id:)`.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/inbox_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Inbox" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:account) { create(:account, business: business) }
  let!(:category) { create(:category, business: business, name: "Software") }
  let!(:txn) { create(:transaction, account: account, payee: "ADOBE CREATIVE", amount_cents: -5499) }
  let!(:done) { create(:transaction, account: account, payee: "ALREADY DONE", category: category) }

  it "lists only inbox transactions" do
    sign_in_as user_with_role("viewer", business)
    get business_inbox_path(business)
    expect(response.body).to include("ADOBE CREATIVE")
    expect(response.body).not_to include("ALREADY DONE")
  end

  it "categorizes with a turbo stream that removes the row" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn),
      params: { outcome: "categorize", category_id: category.id }, as: :turbo_stream
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(action="remove" target="transaction_#{txn.id}"))
    expect(txn.reload.category).to eq(category)
    expect(txn.categorized_by).to eq("user")
  end

  it "marks transfer and exclude with HTML fallback" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn), params: { outcome: "transfer" }
    expect(response).to redirect_to(business_inbox_path(business))
    expect(txn.reload).to be_transfer
    other = create(:transaction, account: account)
    patch business_transaction_classification_path(business, other), params: { outcome: "exclude" }
    expect(other.reload).to be_excluded
  end

  it "asks for a category when none is chosen" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn), params: { outcome: "categorize", category_id: "" }
    expect(flash[:alert]).to eq("Choose a category.")
    expect(txn.reload).to be_inbox
  end

  it "jumps to a prefilled rule form when asked" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn),
      params: { outcome: "categorize", category_id: category.id, make_rule: "1" }, as: :turbo_stream
    expect(response).to redirect_to(new_business_rule_path(business, value: "ADOBE", category_id: category.id))
  end

  it "forbids viewers from classifying" do
    sign_in_as user_with_role("viewer", business)
    patch business_transaction_classification_path(business, txn), params: { outcome: "exclude" }
    expect(response).to have_http_status(:forbidden)
    expect(txn.reload).not_to be_excluded
  end

  it "rejects a category from another business" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn), params: { outcome: "categorize", category_id: create(:category).id }
    expect(flash[:alert]).to eq("Choose a category.")
  end

  describe "household inbox" do
    let!(:other_business) { create(:business, name: "Hidden Biz") }
    let!(:hidden) { create(:transaction, account: create(:account, business: other_business), payee: "SECRET PAYEE") }

    it "shows inbox rows from every accessible business only" do
      sign_in_as user_with_role("editor", business)
      get household_inbox_path
      expect(response.body).to include("ADOBE CREATIVE")
      expect(response.body).not_to include("SECRET PAYEE")
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/inbox_spec.rb`
Expected: FAIL (missing routes / placeholder inbox).

- [ ] **Step 3: Routes**

Inside `resources :businesses do`, change the transactions line to:

```ruby
    resources :transactions, except: :show do
      resource :classification, only: :update
    end
```

At the top level (above `root`):

```ruby
  get "inbox", to: "household_inboxes#show", as: :household_inbox
```

- [ ] **Step 4: Controllers**

`app/controllers/inboxes_controller.rb`:

```ruby
class InboxesController < ApplicationController
  include BusinessScoped

  def show
    @transactions = Transaction.for_businesses(@business.id).inbox.includes(:account).order(posted_on: :desc, id: :desc)
    @categories = @business.categories.active.order(:name)
  end
end
```

`app/controllers/household_inboxes_controller.rb`:

```ruby
class HouseholdInboxesController < ApplicationController
  def show
    businesses = Current.user.accessible_businesses.active.order(:name).to_a
    @memberships = Current.user.memberships.where(business: businesses).index_by(&:business_id)
    @categories = Category.active.where(business: businesses).order(:name).group_by(&:business_id)
    @groups = businesses.map do |business|
      [business, Transaction.for_businesses(business.id).inbox.includes(:account).order(posted_on: :desc, id: :desc).to_a]
    end
  end
end
```

`app/controllers/classifications_controller.rb`:

```ruby
class ClassificationsController < ApplicationController
  include BusinessScoped

  before_action :require_editor!

  def update
    @transaction = Transaction.for_businesses(@business.id).find(params[:transaction_id])
    attrs = classification_attributes
    return redirect_back_or_to(business_inbox_path(@business), alert: "Choose a category.") unless attrs

    @transaction.update!(attrs.merge(categorized_by: "user"))

    if params[:make_rule] == "1" && @transaction.category
      redirect_to new_business_rule_path(@business, value: @transaction.payee.squish.split.first, category_id: @transaction.category_id)
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.remove(@transaction) }
        format.html { redirect_back_or_to business_inbox_path(@business) }
      end
    end
  end

  private

  def classification_attributes
    case params[:outcome]
    when "transfer" then { transfer: true, excluded: false }
    when "exclude" then { excluded: true }
    else
      category = @business.categories.find_by(id: params[:category_id])
      category && { category: category, transfer: false }
    end
  end
end
```

`redirect_back_or_to` with no Referer goes to the fallback, which is what the specs exercise.

- [ ] **Step 5: Views**

`app/views/inboxes/_row.html.erb` (locals: `business`, `txn`, `categories`, `editable`):

```erb
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
    <% end %>
  </td>
</tr>
```

`app/views/inboxes/show.html.erb`:

```erb
<%= business_nav @business %>
<h1>Inbox (<%= @transactions.size %>)</h1>
<% if current_membership.can_edit? %>
  <%= button_to "Apply rules to inbox", apply_business_rules_path(@business) %>
<% end %>
<table>
  <thead><tr><th>Date</th><th>Account</th><th>Payee</th><th class="num">Amount</th><th></th></tr></thead>
  <tbody>
    <% @transactions.each do |txn| %>
      <%= render "inboxes/row", business: @business, txn: txn, categories: @categories, editable: current_membership.can_edit? %>
    <% end %>
  </tbody>
</table>
```

`app/views/household_inboxes/show.html.erb`:

```erb
<h1>Inbox: all businesses</h1>
<% @groups.each do |business, transactions| %>
  <h2><%= link_to business.name, business_inbox_path(business) %> (<%= transactions.size %>)</h2>
  <table>
    <tbody>
      <% transactions.each do |txn| %>
        <%= render "inboxes/row", business: business, txn: txn, categories: @categories.fetch(business.id, []),
              editable: @memberships.fetch(business.id).can_edit? %>
      <% end %>
    </tbody>
  </table>
<% end %>
```

Append to the business nav `<ul>`:

```erb
    <li><%= link_to "Inbox", business_inbox_path(business) %></li>
```

In the layout's `site-nav`, add after "Businesses":

```erb
          <%= link_to "Inbox", household_inbox_path %>
```

- [ ] **Step 6: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add categorization inbox with turbo stream updates"
```

---

### Task 13: CSV parser and mapping (pure)

**Files:**
- Create: `app/models/csv_import/parser.rb`, `app/models/csv_import/mapping.rb`
- Test: `spec/models/csv_import/parser_spec.rb`, `spec/models/csv_import/mapping_spec.rb`

**Interfaces:**
- Consumes: `Money.parse` (Task 2)
- Produces:
  - `CsvImport::Mapping` (ActiveModel): `skip_rows` (int, default 0), `date_column`, `date_format` (key of `Parser::DATE_FORMATS`, default `"MM/DD/YYYY"`), `payee_column`, `memo_column`, `amount_column`, `debit_column`, `credit_column`, `invert_sign` (bool); `#columns → Array<String>`; `#to_h → Hash` (string keys, stored in `accounts.csv_mapping`). Valid only with exactly one amount style (amount column, or both debit and credit).
  - `CsvImport::Parser::DATE_FORMATS` (label → strptime format), `CsvImport::Parser::FileError`
  - `CsvImport::Parser.headers(content, skip_rows: 0) → Array<String>`
  - `CsvImport::Parser.new(mapping, account_id:).parse(content) → Array<Row>`
  - `CsvImport::Parser::Row` (`Data`): `line`, `posted_on`, `amount_cents`, `payee`, `memo`, `external_id`, `error`; `#valid?`; `#rule_attributes`
  - `external_id` = SHA256 hex of `"#{account_id}|#{posted_on.iso8601}|#{amount_cents}|#{payee.downcase}|#{occurrence}"`, where `occurrence` counts earlier identical (date, amount, downcased payee) rows in the same file

- [ ] **Step 1: Write the failing mapping spec**

`spec/models/csv_import/mapping_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CsvImport::Mapping do
  let(:base) { { date_column: "Date", payee_column: "Description" } }

  it "is valid with a single amount column" do
    expect(described_class.new(base.merge(amount_column: "Amount"))).to be_valid
  end

  it "is valid with debit and credit columns" do
    expect(described_class.new(base.merge(debit_column: "Debit", credit_column: "Credit"))).to be_valid
  end

  it "rejects both styles, neither style, or half a split" do
    expect(described_class.new(base.merge(amount_column: "A", debit_column: "D", credit_column: "C"))).not_to be_valid
    expect(described_class.new(base)).not_to be_valid
    expect(described_class.new(base.merge(debit_column: "D"))).not_to be_valid
  end

  it "rejects an unknown date format and negative skip rows" do
    expect(described_class.new(base.merge(amount_column: "A", date_format: "%d.%m"))).not_to be_valid
    expect(described_class.new(base.merge(amount_column: "A", skip_rows: -1))).not_to be_valid
  end

  it "round-trips through a hash" do
    mapping = described_class.new(base.merge(amount_column: "Amount", invert_sign: true))
    again = described_class.new(mapping.to_h)
    expect(again.to_h).to eq(mapping.to_h)
    expect(again.invert_sign).to be(true)
  end
end
```

- [ ] **Step 2: Write the failing parser spec**

`spec/models/csv_import/parser_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CsvImport::Parser do
  let(:mapping) { CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", memo_column: "Memo", amount_column: "Amount") }
  let(:parser) { described_class.new(mapping, account_id: 7) }

  def parse(content, with: parser) = with.parse(content)

  it "parses rows into normalized attributes" do
    rows = parse(<<~CSV)
      Date,Description,Memo,Amount
      01/05/2026,  ADOBE   CREATIVE ,monthly,-54.99
      01/06/2026,Client payment,,"1,500.00"
    CSV
    expect(rows.map { [_1.line, _1.posted_on, _1.payee, _1.memo, _1.amount_cents] }).to eq([
      [2, Date.new(2026, 1, 5), "ADOBE CREATIVE", "monthly", -5499],
      [3, Date.new(2026, 1, 6), "Client payment", nil, 150000]
    ])
    expect(rows).to all(be_valid)
  end

  it "handles a BOM, CRLF line endings, and blank lines" do
    content = "﻿Date,Description,Memo,Amount\r\n01/05/2026,Coffee,,-4.50\r\n\r\n,,,\r\n"
    rows = parse(content)
    expect(rows.size).to eq(1)
    expect(rows.first.amount_cents).to eq(-450)
  end

  it "gives identical rows in one file distinct, repeatable ids" do
    content = <<~CSV
      Date,Description,Memo,Amount
      01/06/2026,Client payment,,100.00
      01/06/2026,Client payment,,100.00
    CSV
    first, second = parse(content)
    expect(first.external_id).not_to eq(second.external_id)
    expect(parse(content).map(&:external_id)).to eq([first.external_id, second.external_id])
  end

  it "gives the same id to the same row in an overlapping file" do
    jan = parse("Date,Description,Memo,Amount\n01/05/2026,Coffee,,-4.50\n01/07/2026,Tea,,-3.00\n")
    overlap = parse("Date,Description,Memo,Amount\n01/07/2026,Tea,,-3.00\n01/09/2026,Cake,,-6.00\n")
    expect(overlap.first.external_id).to eq(jan.last.external_id)
  end

  it "scopes ids to the account" do
    other = described_class.new(mapping, account_id: 8)
    content = "Date,Description,Memo,Amount\n01/05/2026,Coffee,,-4.50\n"
    expect(parse(content).first.external_id).not_to eq(parse(content, with: other).first.external_id)
  end

  it "supports debit and credit columns" do
    split = CsvImport::Mapping.new(date_column: "Date", payee_column: "Payee", debit_column: "Debit", credit_column: "Credit")
    rows = described_class.new(split, account_id: 1).parse("Date,Payee,Debit,Credit\n01/05/2026,Store,12.00,\n01/06/2026,Client,,500\n")
    expect(rows.map(&:amount_cents)).to eq([-1200, 50000])
  end

  it "inverts signs for card statements" do
    mapping.invert_sign = true
    expect(parse("Date,Description,Memo,Amount\n01/05/2026,Store,,12.00\n").first.amount_cents).to eq(-1200)
  end

  it "skips preamble rows" do
    mapping.skip_rows = 2
    rows = parse("Bank of Example\nAccount 1234\nDate,Description,Memo,Amount\n01/05/2026,Store,,-1\n")
    expect(rows.first.line).to eq(4)
    expect(rows.first.payee).to eq("Store")
  end

  it "uses the chosen date format" do
    mapping.date_format = "YYYY-MM-DD"
    expect(parse("Date,Description,Memo,Amount\n2026-01-05,Store,,-1\n").first.posted_on).to eq(Date.new(2026, 1, 5))
  end

  it "reports bad rows with their line numbers instead of dropping them" do
    rows = parse(<<~CSV)
      Date,Description,Memo,Amount
      13/45/2026,Bad date,,-1
      01/05/2026,Bad amount,,abc
      01/05/2026,,,-1
      01/05/2026,Fine,,-1
    CSV
    expect(rows.map { [_1.line, _1.error] }).to eq([
      [2, "Invalid date"], [3, "Amount is not a valid amount"], [4, "Missing payee"], [5, nil]
    ])
    expect(rows.first.external_id).to be_nil
  end

  it "raises FileError for non-UTF-8 content" do
    expect { parse("Date,Description\n\xFF\xFE".b) }.to raise_error(CsvImport::Parser::FileError, "File must be UTF-8 encoded.")
  end

  it "raises FileError when a mapped column is missing" do
    expect { parse("Date,Payee,Amount\n01/05/2026,Store,-1\n") }.to raise_error(CsvImport::Parser::FileError, "Column not found: Description, Memo")
  end

  it "raises FileError for an empty file" do
    expect { parse("") }.to raise_error(CsvImport::Parser::FileError, "File has no header row.")
  end

  it "reads headers after skipped rows" do
    expect(described_class.headers("junk\n Date , Amount\n1,2\n", skip_rows: 1)).to eq(["Date", "Amount"])
  end

  it "exposes rule attributes" do
    row = parse("Date,Description,Memo,Amount\n01/05/2026,Store,x,-1\n").first
    expect(row.rule_attributes).to eq(payee: "Store", memo: "x", amount_cents: -100)
  end
end
```

- [ ] **Step 3: Run them to verify they fail**

Run: `bundle exec rspec spec/models/csv_import`
Expected: FAIL with `uninitialized constant CsvImport`.

- [ ] **Step 4: Implement**

`app/models/csv_import/parser.rb`:

```ruby
require "csv"

class CsvImport::Parser
  DATE_FORMATS = {
    "MM/DD/YYYY" => "%m/%d/%Y",
    "YYYY-MM-DD" => "%Y-%m-%d",
    "MM/DD/YY" => "%m/%d/%y",
    "DD/MM/YYYY" => "%d/%m/%Y"
  }.freeze

  class FileError < StandardError; end

  Row = Data.define(:line, :posted_on, :amount_cents, :payee, :memo, :external_id, :error) do
    def valid? = error.nil?
    def rule_attributes = { payee: payee, memo: memo, amount_cents: amount_cents }
  end

  def self.table(content, skip_rows: 0)
    text = content.to_s.dup.force_encoding(Encoding::UTF_8)
    raise FileError, "File must be UTF-8 encoded." unless text.valid_encoding?

    CSV.parse(text.delete_prefix("﻿"), liberal_parsing: true).drop(skip_rows)
  rescue CSV::MalformedCSVError => e
    raise FileError, "Could not read CSV: #{e.message}"
  end

  def self.headers(content, skip_rows: 0)
    table(content, skip_rows: skip_rows).first.to_a.map { _1.to_s.strip }
  end

  def initialize(mapping, account_id:)
    @mapping = mapping
    @account_id = account_id
  end

  def parse(content)
    header, *data = self.class.table(content, skip_rows: @mapping.skip_rows.to_i)
    raise FileError, "File has no header row." if header.nil?

    @columns = header.map { _1.to_s.strip }
    missing = @mapping.columns - @columns
    raise FileError, "Column not found: #{missing.join(", ")}" if missing.any?

    occurrences = Hash.new(0)
    data.each_with_index.filter_map do |cells, index|
      next if cells.all? { _1.to_s.strip.empty? }

      build_row(cells, @mapping.skip_rows.to_i + index + 2, occurrences)
    end
  end

  private

  def build_row(cells, line, occurrences)
    payee = cell(cells, @mapping.payee_column).squish
    memo = cell(cells, @mapping.memo_column).squish.presence
    failure = ->(message) { Row.new(line:, posted_on: nil, amount_cents: nil, payee:, memo:, external_id: nil, error: message) }

    posted_on = parse_date(cell(cells, @mapping.date_column))
    return failure.("Invalid date") unless posted_on

    amount_cents = begin
      parse_amount(cells)
    rescue Money::ParseError => e
      return failure.("Amount #{e.message}")
    end
    return failure.("Missing payee") if payee.empty?

    key = [posted_on, amount_cents, payee.downcase]
    occurrence = occurrences[key]
    occurrences[key] += 1
    Row.new(line:, posted_on:, amount_cents:, payee:, memo:, external_id: external_id(key, occurrence), error: nil)
  end

  def cell(cells, column)
    return "" if column.blank?

    cells[@columns.index(column)].to_s.strip
  end

  def parse_date(value)
    Date.strptime(value, DATE_FORMATS.fetch(@mapping.date_format))
  rescue Date::Error
    nil
  end

  def parse_amount(cells)
    cents =
      if @mapping.amount_column.present?
        Money.parse(cell(cells, @mapping.amount_column)).cents
      else
        debit = cell(cells, @mapping.debit_column)
        credit = cell(cells, @mapping.credit_column)
        if debit.present? then -Money.parse(debit).cents.abs
        elsif credit.present? then Money.parse(credit).cents.abs
        else raise Money::ParseError, "can't be blank"
        end
      end
    @mapping.invert_sign ? -cents : cents
  end

  def external_id(key, occurrence)
    posted_on, amount_cents, payee = key
    Digest::SHA256.hexdigest([@account_id, posted_on.iso8601, amount_cents, payee, occurrence].join("|"))
  end
end
```

`app/models/csv_import/mapping.rb`:

```ruby
class CsvImport::Mapping
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :skip_rows, :integer, default: 0
  attribute :date_column, :string
  attribute :date_format, :string, default: "MM/DD/YYYY"
  attribute :payee_column, :string
  attribute :memo_column, :string
  attribute :amount_column, :string
  attribute :debit_column, :string
  attribute :credit_column, :string
  attribute :invert_sign, :boolean, default: false

  validates :date_column, :payee_column, presence: true
  validates :date_format, inclusion: { in: CsvImport::Parser::DATE_FORMATS.keys }
  validates :skip_rows, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :one_amount_style

  def columns
    [date_column, payee_column, memo_column, amount_column, debit_column, credit_column].compact_blank
  end

  def to_h = attributes

  private

  def one_amount_style
    single = amount_column.present?
    split = debit_column.present? && credit_column.present?
    partial = debit_column.present? ^ credit_column.present?
    return if (single ^ split) && !partial

    errors.add(:base, "Choose an amount column, or both a debit and a credit column")
  end
end
```

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/models/csv_import`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add pure CSV parser and column mapping"
```

---

### Task 14: CSV import flow (upload → map → preview → commit)

**Files:**
- Run: `bin/rails active_storage:install`
- Create: migration `create_csv_imports`; `app/models/csv_import.rb`; `app/models/csv_import/preview.rb`; `app/controllers/csv_imports_controller.rb`; `app/controllers/csv_import_mappings_controller.rb`; views `app/views/csv_imports/{new,show}.html.erb`, `app/views/csv_import_mappings/edit.html.erb`; `spec/fixtures/files/checking.csv`
- Modify: `app/models/account.rb`, `config/routes.rb`, `app/views/accounts/index.html.erb`
- Test: `spec/models/csv_import_spec.rb`, `spec/requests/csv_imports_spec.rb`, `spec/system/csv_import_spec.rb`

**Interfaces:**
- Consumes: `CsvImport::Parser`, `CsvImport::Mapping` (Task 13), `RuleEngine` (Task 10), `RuleApplier` (Task 11)
- Produces:
  - `CsvImport` (`account`, `file` attachment, `status` `previewed|committed|discarded`, `row_count`, `new_count`, `duplicate_count`, `error_count`, `committed_at`), `CsvImport::MAX_BYTES = 5.megabytes`, `#content`, `#preview → CsvImport::Preview`, `#commit!` (raises `CsvImport::NotPreviewed` unless previewed)
  - `CsvImport::Preview.build(csv_import)`, with `#entries` (each `Entry(row, status, proposed_rule)`, status `:new|:duplicate|:error`), `#new_entries`, `#duplicate_entries`, `#error_entries`
  - `Account#mapping → CsvImport::Mapping`, `#mapped?`, `#csv_imports`
  - Routes: `new_business_account_csv_import_path(b, a)`, `business_account_csv_import_path(b, a, i)`, `commit_business_account_csv_import_path`, `edit_business_account_csv_import_mapping_path(b, a, i)`, `business_account_csv_import_mapping_path`

- [ ] **Step 1: Install Active Storage and migrate**

```bash
bin/rails active_storage:install
bin/rails generate migration CreateCsvImports
```

```ruby
class CreateCsvImports < ActiveRecord::Migration[8.1]
  def change
    create_table :csv_imports do |t|
      t.references :account, null: false, foreign_key: true
      t.string :status, null: false, default: "previewed"
      t.integer :row_count, null: false, default: 0
      t.integer :new_count, null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.datetime :committed_at
      t.timestamps
    end
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Fixture**

`spec/fixtures/files/checking.csv`:

```
Date,Description,Amount
01/05/2026,ADOBE CREATIVE CLOUD,-54.99
01/06/2026,Client payment ACME,"1,500.00"
01/06/2026,Client payment ACME,"1,500.00"
01/07/2026,COFFEE SHOP,-4.50
```

- [ ] **Step 3: Write the failing model spec**

`spec/models/csv_import_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CsvImport do
  let(:business) { create(:business) }
  let(:software) { create(:category, business: business, name: "Software") }
  let(:account) do
    create(:account, :csv, business: business,
      csv_mapping: CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount").to_h)
  end
  let(:fixture) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/checking.csv"), "text/csv") }

  def upload = account.csv_imports.create!(file: fixture)

  it "rejects files over 5 MB" do
    big = Rack::Test::UploadedFile.new(StringIO.new("a" * (CsvImport::MAX_BYTES + 1)), "text/csv", original_filename: "big.csv")
    import = account.csv_imports.new(file: big)
    expect(import).not_to be_valid
    expect(import.errors[:file]).to include("must be 5 MB or smaller")
  end

  it "requires a file" do
    expect(account.csv_imports.new).not_to be_valid
  end

  it "previews new rows with proposed rules" do
    create(:rule, business: business, value: "adobe", category: software)
    preview = upload.preview
    expect(preview.new_entries.size).to eq(4)
    expect(preview.new_entries.first.proposed_rule.category).to eq(software)
  end

  it "commits new rows, applies rules, and records counts" do
    create(:rule, business: business, value: "adobe", category: software)
    import = upload
    import.commit!
    expect(account.transactions.count).to eq(4)
    expect(account.transactions.find_by!(payee: "ADOBE CREATIVE CLOUD").category).to eq(software)
    expect(import.reload).to be_committed
    expect([import.row_count, import.new_count, import.duplicate_count, import.error_count]).to eq([4, 4, 0, 0])
  end

  it "imports nothing new the second time" do
    upload.commit!
    second = upload
    expect(second.preview.duplicate_entries.size).to eq(4)
    second.commit!
    expect(account.transactions.count).to eq(4)
    expect(second.reload.new_count).to eq(0)
  end

  it "refuses to commit twice" do
    import = upload
    import.commit!
    expect { import.commit! }.to raise_error(CsvImport::NotPreviewed)
  end
end
```

- [ ] **Step 4: Run it to verify it fails**

Run: `bundle exec rspec spec/models/csv_import_spec.rb`
Expected: FAIL (`CsvImport` is a module without `csv_imports` / `NameError`).

- [ ] **Step 5: Implement model and preview**

`app/models/csv_import.rb`:

```ruby
class CsvImport < ApplicationRecord
  MAX_BYTES = 5.megabytes

  class NotPreviewed < StandardError; end

  belongs_to :account
  has_one_attached :file

  enum :status, { previewed: "previewed", committed: "committed", discarded: "discarded" }, validate: true

  validate :file_present_and_small, on: :create

  def content = file.download

  def preview = CsvImport::Preview.build(self)

  def commit!
    raise NotPreviewed, "This import was already #{status}." unless previewed?

    result = preview
    ApplicationRecord.transaction do
      created = result.new_entries.map do |entry|
        row = entry.row
        account.transactions.create!(posted_on: row.posted_on, amount_cents: row.amount_cents, payee: row.payee,
                                     memo: row.memo, external_id: row.external_id)
      end
      RuleApplier.new(account.business).apply(created)
      update!(status: "committed", committed_at: Time.current, row_count: result.entries.size, new_count: created.size,
              duplicate_count: result.duplicate_entries.size, error_count: result.error_entries.size)
    end
  end

  private

  def file_present_and_small
    if !file.attached?
      errors.add(:file, "must be attached")
    elsif file.blob.byte_size > MAX_BYTES
      errors.add(:file, "must be 5 MB or smaller")
    end
  end
end
```

`app/models/csv_import/preview.rb`:

```ruby
class CsvImport::Preview
  Entry = Data.define(:row, :status, :proposed_rule)

  attr_reader :entries

  def self.build(csv_import)
    account = csv_import.account
    rows = CsvImport::Parser.new(account.mapping, account_id: account.id).parse(csv_import.content)
    existing = account.transactions.where(external_id: rows.filter_map(&:external_id)).pluck(:external_id).to_set
    rules = account.business.rules.ordered.includes(:category).to_a

    new(rows.map do |row|
      if !row.valid? then Entry.new(row:, status: :error, proposed_rule: nil)
      elsif existing.include?(row.external_id) then Entry.new(row:, status: :duplicate, proposed_rule: nil)
      else Entry.new(row:, status: :new, proposed_rule: RuleEngine.match(row.rule_attributes, rules))
      end
    end)
  end

  def initialize(entries)
    @entries = entries
  end

  def new_entries = entries.select { _1.status == :new }
  def duplicate_entries = entries.select { _1.status == :duplicate }
  def error_entries = entries.select { _1.status == :error }
end
```

Add to `app/models/account.rb`:

```ruby
  has_many :csv_imports, dependent: :destroy

  def mapping = CsvImport::Mapping.new(csv_mapping || {})

  def mapped? = csv_mapping.present?
```

Run: `bundle exec rspec spec/models/csv_import_spec.rb`
Expected: PASS.

- [ ] **Step 6: Write the failing request and system specs**

`spec/requests/csv_imports_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "CSV imports" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, :csv, business: business) }
  let(:fixture) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/checking.csv"), "text/csv") }

  it "sends an unmapped account to the mapping step" do
    sign_in_as user_with_role("editor", business)
    post business_account_csv_imports_path(business, account), params: { csv_import: { file: fixture } }
    import = account.csv_imports.sole
    expect(response).to redirect_to(edit_business_account_csv_import_mapping_path(business, account, import))
  end

  it "re-renders the mapping with errors" do
    sign_in_as user_with_role("editor", business)
    post business_account_csv_imports_path(business, account), params: { csv_import: { file: fixture } }
    import = account.csv_imports.sole
    patch business_account_csv_import_mapping_path(business, account, import),
      params: { csv_import_mapping: { date_column: "Date", payee_column: "", amount_column: "Amount", date_format: "MM/DD/YYYY" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "shows a readable error for a broken file" do
    account.update!(csv_mapping: CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount").to_h)
    sign_in_as user_with_role("editor", business)
    bad = Rack::Test::UploadedFile.new(StringIO.new("Date,Nope\n1,2\n"), "text/csv", original_filename: "bad.csv")
    post business_account_csv_imports_path(business, account), params: { csv_import: { file: bad } }
    follow_redirect!
    expect(response.body).to include("Column not found: Description, Amount")
  end

  it "forbids viewers" do
    sign_in_as user_with_role("viewer", business)
    get new_business_account_csv_import_path(business, account)
    expect(response).to have_http_status(:forbidden)
    post business_account_csv_imports_path(business, account), params: { csv_import: { file: fixture } }
    expect(response).to have_http_status(:forbidden)
  end

  it "is not found for manual accounts" do
    cash = create(:account, business: business, source: "manual")
    sign_in_as user_with_role("editor", business)
    get new_business_account_csv_import_path(business, cash)
    expect(response).to have_http_status(:not_found)
  end
end
```

`spec/system/csv_import_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Importing a CSV statement" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, :csv, business: business, name: "Checking") }
  let!(:software) { create(:category, business: business, name: "Software", schedule_c_line: "27a") }
  let!(:rule) { create(:rule, business: business, value: "adobe", category: software) }
  let(:editor) { user_with_role("editor", business) }
  let(:csv_path) { Rails.root.join("spec/fixtures/files/checking.csv") }

  def upload
    visit business_accounts_path(business)
    click_on "Import CSV"
    attach_file "csv_import[file]", csv_path
    click_on "Upload"
  end

  it "maps, previews, commits, and skips duplicates on re-import" do
    system_sign_in_as editor
    upload

    select "Date", from: "Date column"
    select "Description", from: "Payee column"
    select "Amount", from: "Amount column"
    select "MM/DD/YYYY", from: "Date format"
    click_on "Save mapping"

    expect(page).to have_content("4 new")
    expect(page).to have_content("Software")
    click_on "Import"
    expect(page).to have_content("Imported 4 new transactions (0 duplicates skipped, 0 rows with errors).")
    expect(account.transactions.find_by!(payee: "ADOBE CREATIVE CLOUD").category).to eq(software)

    upload
    expect(page).to have_content("0 new")
    expect(page).to have_content("4 duplicates")
    click_on "Import"
    expect(account.transactions.count).to eq(4)
  end
end
```

- [ ] **Step 7: Run them to verify they fail**

Run: `bundle exec rspec spec/requests/csv_imports_spec.rb spec/system/csv_import_spec.rb`
Expected: FAIL (no routes).

- [ ] **Step 8: Routes, controllers, views**

In `config/routes.rb`, replace the accounts line inside `resources :businesses do`:

```ruby
    resources :accounts, only: %i[index new create edit update] do
      resources :csv_imports, only: %i[new create show destroy] do
        post :commit, on: :member
        resource :mapping, only: %i[edit update], controller: "csv_import_mappings"
      end
    end
```

`app/controllers/csv_imports_controller.rb`:

```ruby
class CsvImportsController < ApplicationController
  include BusinessScoped

  before_action :require_editor!
  before_action :set_account
  before_action :set_import, only: %i[show commit destroy]

  def new
    @import = @account.csv_imports.new
  end

  def create
    @import = @account.csv_imports.new(file: params.dig(:csv_import, :file))
    if @import.save
      redirect_to @account.mapped? ? import_path : edit_business_account_csv_import_mapping_path(@business, @account, @import)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    return redirect_to edit_business_account_csv_import_mapping_path(@business, @account, @import) unless @account.mapped?

    @preview = @import.preview
  rescue CsvImport::Parser::FileError => e
    @file_error = e.message
  end

  def commit
    @import.commit!
    redirect_to business_transactions_path(@business, account_id: @account.id),
      notice: "Imported #{@import.new_count} new transactions (#{@import.duplicate_count} duplicates skipped, " \
              "#{@import.error_count} rows with errors)."
  rescue CsvImport::NotPreviewed, CsvImport::Parser::FileError => e
    redirect_to import_path, alert: e.message
  end

  def destroy
    @import.update!(status: "discarded")
    @import.file.purge
    redirect_to business_accounts_path(@business), notice: "Import discarded.", status: :see_other
  end

  private

  def set_account
    @account = @business.accounts.csv.find(params[:account_id])
  end

  def set_import
    @import = @account.csv_imports.find(params[:id])
  end

  def import_path = business_account_csv_import_path(@business, @account, @import)
end
```

`app/controllers/csv_import_mappings_controller.rb`:

```ruby
class CsvImportMappingsController < ApplicationController
  include BusinessScoped

  PERMITTED = %i[skip_rows date_column date_format payee_column memo_column amount_column debit_column credit_column invert_sign].freeze

  before_action :require_editor!
  before_action :set_import

  def edit
    @mapping = @account.mapping
    @mapping.skip_rows = params[:skip_rows].to_i if params[:skip_rows].present?
    load_headers
  end

  def update
    @mapping = CsvImport::Mapping.new(params.expect(csv_import_mapping: PERMITTED))
    if @mapping.valid?
      @account.update!(csv_mapping: @mapping.to_h)
      redirect_to business_account_csv_import_path(@business, @account, @import)
    else
      load_headers
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_import
    @account = @business.accounts.csv.find(params[:account_id])
    @import = @account.csv_imports.find(params[:csv_import_id])
  end

  def load_headers
    @headers = CsvImport::Parser.headers(@import.content, skip_rows: @mapping.skip_rows.to_i)
  rescue CsvImport::Parser::FileError => e
    @headers = []
    @file_error = e.message
  end
end
```

`app/views/csv_imports/new.html.erb`:

```erb
<%= business_nav @business %>
<h1>Import CSV into <%= @account.name %></h1>
<%= form_with model: @import, url: business_account_csv_imports_path(@business, @account) do |f| %>
  <%= render "shared/errors", record: @import %>
  <p><%= f.file_field :file, accept: ".csv,text/csv", required: true %></p>
  <%= f.submit "Upload" %>
<% end %>
```

`app/views/csv_import_mappings/edit.html.erb`:

```erb
<%= business_nav @business %>
<h1>Map columns for <%= @account.name %></h1>
<% if @file_error %><p class="errors"><%= @file_error %></p><% end %>
<%= form_with url: edit_business_account_csv_import_mapping_path(@business, @account, @import), method: :get, class: "inline-form" do |f| %>
  <%= f.label :skip_rows, "Rows to skip before the header" %>
  <%= f.number_field :skip_rows, value: @mapping.skip_rows, min: 0 %>
  <%= f.submit "Reload columns" %>
<% end %>
<%= form_with model: @mapping, scope: :csv_import_mapping, url: business_account_csv_import_mapping_path(@business, @account, @import), method: :patch do |f| %>
  <%= render "shared/errors", record: @mapping %>
  <%= f.hidden_field :skip_rows %>
  <p><%= f.label :date_column, "Date column" %> <%= f.select :date_column, @headers, include_blank: true %></p>
  <p><%= f.label :date_format, "Date format" %> <%= f.select :date_format, CsvImport::Parser::DATE_FORMATS.keys %></p>
  <p><%= f.label :payee_column, "Payee column" %> <%= f.select :payee_column, @headers, include_blank: true %></p>
  <p><%= f.label :memo_column, "Memo column (optional)" %> <%= f.select :memo_column, @headers, include_blank: true %></p>
  <p><%= f.label :amount_column, "Amount column" %> <%= f.select :amount_column, @headers, include_blank: true %></p>
  <p>…or separate columns:
    <%= f.label :debit_column, "Debit column" %> <%= f.select :debit_column, @headers, include_blank: true %>
    <%= f.label :credit_column, "Credit column" %> <%= f.select :credit_column, @headers, include_blank: true %>
  </p>
  <p><%= f.label :invert_sign, "Invert signs (credit card statements that show purchases as positive)" %> <%= f.check_box :invert_sign %></p>
  <%= f.submit "Save mapping" %>
<% end %>
```

`app/views/csv_imports/show.html.erb`:

```erb
<%= business_nav @business %>
<h1>Preview import into <%= @account.name %></h1>
<% if @file_error %>
  <p class="errors"><%= @file_error %></p>
<% elsif @import.previewed? %>
  <p>
    <%= @preview.new_entries.size %> new ·
    <%= pluralize(@preview.duplicate_entries.size, "duplicate") %> ·
    <%= pluralize(@preview.error_entries.size, "row") %> with errors
  </p>
  <table>
    <thead><tr><th>Line</th><th>Date</th><th>Payee</th><th class="num">Amount</th><th>Status</th><th>Rule</th></tr></thead>
    <tbody>
      <% @preview.entries.each do |entry| %>
        <tr>
          <td><%= entry.row.line %></td>
          <td><%= entry.row.posted_on %></td>
          <td><%= entry.row.payee %></td>
          <td class="num"><%= money(entry.row.amount_cents) %></td>
          <td><%= entry.status == :error ? entry.row.error : entry.status %></td>
          <td><%= entry.proposed_rule && (entry.proposed_rule.outcome == "transfer" ? "Transfer" : entry.proposed_rule.category.name) %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= button_to "Import", commit_business_account_csv_import_path(@business, @account, @import) %>
<% else %>
  <p>This import was <%= @import.status %>.</p>
<% end %>
<%= link_to "Change column mapping", edit_business_account_csv_import_mapping_path(@business, @account, @import) %>
<% if @import.previewed? %>
  <%= button_to "Discard", business_account_csv_import_path(@business, @account, @import), method: :delete %>
<% end %>
```

In `app/views/accounts/index.html.erb`, change the last cell of each row to:

```erb
        <td>
          <%= link_to "Import CSV", new_business_account_csv_import_path(@business, account) if account.csv? && current_membership.can_edit? %>
          <%= link_to "Edit", edit_business_account_path(@business, account) if current_membership.owner? %>
        </td>
```

- [ ] **Step 9: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS, clean output (Active Storage writes to `tmp/storage` silently).

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "Add CSV import flow with mapping, preview, and duplicate detection"
```

---

### Task 15: Tax parameters (mileage rate) and the mileage log

**Files:**
- Create: migrations `create_tax_parameters`, `create_mileage_entries`; `app/models/tenths.rb`; `app/models/mileage_deduction.rb`; `app/models/tax_parameters.rb`; `app/models/mileage_entry.rb`; `app/controllers/tax_parameters_controller.rb`; `app/controllers/mileage_entries_controller.rb`; views for both; `spec/factories/{tax_parameters,mileage_entries}.rb`
- Modify: `app/models/business.rb`, `config/routes.rb`, `app/views/businesses/_nav.html.erb`, `app/views/layouts/application.html.erb`
- Test: `spec/models/tenths_spec.rb`, `spec/models/mileage_deduction_spec.rb`, `spec/models/mileage_entry_spec.rb`, `spec/requests/mileage_entries_spec.rb`, `spec/requests/tax_parameters_spec.rb`

**Interfaces:**
- Consumes: `Money.round_rational` (Task 2)
- Produces:
  - `Tenths.parse(string) → Integer` (raises `Tenths::ParseError`), `Tenths.format(integer) → "12.3"`
  - `MileageDeduction.cents(miles_tenths:, rate_tenth_cents:) → Integer`
  - `TaxParameters` (table `tax_parameters`; `year` unique, `standard_mileage_rate_tenth_cents`), `#mileage_rate_cents` / `=` (string `"72.5"` ↔ 725), `TaxParameters.for_year(year)`. Form param key: `tax_parameter`.
  - `MileageEntry` (`business`, `driven_on`, `purpose`, `from_location`, `to_location`, `miles_tenths`, `round_trip`), `#miles` / `#miles=`, `#effective_miles_tenths`
  - `Business#mileage_entries`
  - Routes: `business_mileage_entries_path(b, year:)`, `tax_parameters_path`, `new_tax_parameter_path`, `edit_tax_parameter_path(tp)`

- [ ] **Step 1: Migrations**

```bash
bin/rails generate migration CreateTaxParameters
bin/rails generate migration CreateMileageEntries
```

```ruby
class CreateTaxParameters < ActiveRecord::Migration[8.1]
  def change
    create_table :tax_parameters do |t|
      t.integer :year, null: false, index: { unique: true }
      t.integer :standard_mileage_rate_tenth_cents, null: false
      t.timestamps
    end
  end
end
```

```ruby
class CreateMileageEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :mileage_entries do |t|
      t.references :business, null: false, foreign_key: true
      t.date :driven_on, null: false
      t.string :purpose, null: false
      t.string :from_location
      t.string :to_location
      t.integer :miles_tenths, null: false
      t.boolean :round_trip, null: false, default: false
      t.timestamps
    end
    add_index :mileage_entries, :driven_on
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Factories**

`spec/factories/tax_parameters.rb`:

```ruby
FactoryBot.define do
  factory :tax_parameters do
    year { 2026 }
    standard_mileage_rate_tenth_cents { 725 }
  end
end
```

`spec/factories/mileage_entries.rb`:

```ruby
FactoryBot.define do
  factory :mileage_entry do
    business
    driven_on { Date.new(2026, 3, 2) }
    purpose { "Client meeting" }
    from_location { "Home office" }
    to_location { "Client" }
    miles_tenths { 100 }
  end
end
```

- [ ] **Step 3: Write failing unit specs**

`spec/models/tenths_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Tenths do
  it { expect(Tenths.parse("12.3")).to eq(123) }
  it { expect(Tenths.parse("12")).to eq(120) }
  it { expect(Tenths.parse(" .5 ")).to eq(5) }
  it { expect(Tenths.parse("1,200.5")).to eq(12005) }

  ["", "abc", "1.25", "-3", "1.2.3"].each do |bad|
    it "rejects #{bad.inspect}" do
      expect { Tenths.parse(bad) }.to raise_error(Tenths::ParseError)
    end
  end

  it { expect(Tenths.format(725)).to eq("72.5") }
  it { expect(Tenths.format(5)).to eq("0.5") }
end
```

`spec/models/mileage_deduction_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe MileageDeduction do
  it "multiplies tenths of miles by tenths of cents and rounds once, half up" do
    # 123.4 miles × 72.5¢ = 8946.5¢ → 8947¢
    expect(MileageDeduction.cents(miles_tenths: 1234, rate_tenth_cents: 725)).to eq(8947)
  end

  it "is zero for zero miles" do
    expect(MileageDeduction.cents(miles_tenths: 0, rate_tenth_cents: 725)).to eq(0)
  end
end
```

`spec/models/mileage_entry_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe MileageEntry do
  it "parses miles and doubles round trips" do
    entry = build(:mileage_entry, miles: "18.4", round_trip: true)
    expect(entry.miles_tenths).to eq(184)
    expect(entry.effective_miles_tenths).to eq(368)
  end

  it "reports bad miles" do
    entry = build(:mileage_entry, miles: "lots")
    expect(entry).not_to be_valid
    expect(entry.errors[:miles]).to include("must be a number with at most one decimal place")
  end

  it "requires a purpose and positive miles" do
    expect(build(:mileage_entry, purpose: "")).not_to be_valid
    expect(build(:mileage_entry, miles_tenths: 0)).not_to be_valid
  end
end
```

Run: `bundle exec rspec spec/models/tenths_spec.rb spec/models/mileage_deduction_spec.rb spec/models/mileage_entry_spec.rb`
Expected: FAIL (`uninitialized constant Tenths`).

- [ ] **Step 4: Implement the models**

`app/models/tenths.rb`:

```ruby
module Tenths
  class ParseError < ArgumentError; end

  module_function

  def parse(input)
    text = input.to_s.strip.delete(",")
    raise ParseError, "can't be blank" if text.empty?

    match = text.match(/\A(\d*)(?:\.(\d))?\z/)
    if match.nil? || (match[1].empty? && match[2].nil?)
      raise ParseError, "must be a number with at most one decimal place"
    end

    match[1].to_i * 10 + match[2].to_i
  end

  def format(tenths) = "#{tenths / 10}.#{tenths % 10}"
end
```

`app/models/mileage_deduction.rb`:

```ruby
module MileageDeduction
  def self.cents(miles_tenths:, rate_tenth_cents:)
    Money.round_rational(Rational(miles_tenths * rate_tenth_cents, 100))
  end
end
```

`app/models/tax_parameters.rb`:

```ruby
class TaxParameters < ApplicationRecord
  self.table_name = "tax_parameters"

  validates :year, presence: true, uniqueness: true, numericality: { only_integer: true, in: 2000..2100 }
  validates :standard_mileage_rate_tenth_cents, numericality: { only_integer: true, greater_than: 0 }
  validate { errors.add(:mileage_rate_cents, @mileage_rate_error) if @mileage_rate_error }

  def self.for_year(year) = find_by(year: year)

  def self.model_name = ActiveModel::Name.new(self, nil, "TaxParameter")

  def mileage_rate_cents
    @mileage_rate_input || (standard_mileage_rate_tenth_cents && Tenths.format(standard_mileage_rate_tenth_cents))
  end

  def mileage_rate_cents=(input)
    @mileage_rate_input = input
    @mileage_rate_error = nil
    self.standard_mileage_rate_tenth_cents = Tenths.parse(input)
  rescue Tenths::ParseError => e
    @mileage_rate_error = e.message
  end
end
```

(`model_name` override makes routes/forms use `tax_parameter` / `tax_parameters`.)

`app/models/mileage_entry.rb`:

```ruby
class MileageEntry < ApplicationRecord
  belongs_to :business

  validates :driven_on, :purpose, presence: true
  validates :miles_tenths, numericality: { only_integer: true, greater_than: 0 }
  validate { errors.add(:miles, @miles_error) if @miles_error }

  def miles
    @miles_input || (miles_tenths && Tenths.format(miles_tenths))
  end

  def miles=(input)
    @miles_input = input
    @miles_error = nil
    self.miles_tenths = Tenths.parse(input)
  rescue Tenths::ParseError => e
    self.miles_tenths = nil
    @miles_error = e.message
  end

  def effective_miles_tenths = round_trip? ? miles_tenths * 2 : miles_tenths
end
```

Add to `app/models/business.rb`:

```ruby
  has_many :mileage_entries, dependent: :destroy
```

Run the three model specs again. Expected: PASS.

- [ ] **Step 5: Write failing request specs**

`spec/requests/mileage_entries_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Mileage" do
  let!(:business) { create(:business) }

  it "lists the year's entries with the deduction" do
    create(:tax_parameters, year: 2026, standard_mileage_rate_tenth_cents: 725)
    create(:mileage_entry, business: business, miles_tenths: 1234)
    sign_in_as user_with_role("viewer", business)
    get business_mileage_entries_path(business, year: 2026)
    expect(response.body).to include("123.4")
    expect(response.body).to include("$89.47")
  end

  it "asks for the rate when the year has none" do
    create(:mileage_entry, business: business)
    sign_in_as user_with_role("viewer", business)
    get business_mileage_entries_path(business, year: 2026)
    expect(response.body).to include("No IRS mileage rate is set for 2026")
  end

  it "lets editors log a round trip" do
    sign_in_as user_with_role("editor", business)
    post business_mileage_entries_path(business), params: { mileage_entry: {
      driven_on: "2026-03-02", purpose: "Site visit", from_location: "Home", to_location: "Client", miles: "12.5", round_trip: "1"
    } }
    expect(response).to redirect_to(business_mileage_entries_path(business, year: 2026))
    expect(business.mileage_entries.sole.effective_miles_tenths).to eq(250)
  end

  it "re-renders bad miles" do
    sign_in_as user_with_role("editor", business)
    post business_mileage_entries_path(business), params: { mileage_entry: { driven_on: "2026-03-02", purpose: "X", miles: "far" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "forbids viewers from writing" do
    entry = create(:mileage_entry, business: business)
    sign_in_as user_with_role("viewer", business)
    post business_mileage_entries_path(business), params: { mileage_entry: { purpose: "X" } }
    expect(response).to have_http_status(:forbidden)
    delete business_mileage_entry_path(business, entry)
    expect(response).to have_http_status(:forbidden)
  end
end
```

`spec/requests/tax_parameters_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Tax parameters" do
  let!(:business) { create(:business) }

  it "lets the household owner set a year's mileage rate" do
    sign_in_as create(:user, :household_owner)
    post tax_parameters_path, params: { tax_parameter: { year: "2027", mileage_rate_cents: "73" } }
    expect(response).to redirect_to(tax_parameters_path)
    expect(TaxParameters.for_year(2027).standard_mileage_rate_tenth_cents).to eq(730)
  end

  it "rejects a malformed rate" do
    sign_in_as create(:user, :household_owner)
    post tax_parameters_path, params: { tax_parameter: { year: "2027", mileage_rate_cents: "72.55" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "forbids everyone else, even business owners" do
    sign_in_as user_with_role("owner", business)
    get tax_parameters_path
    expect(response).to have_http_status(:forbidden)
  end
end
```

Run: `bundle exec rspec spec/requests/mileage_entries_spec.rb spec/requests/tax_parameters_spec.rb`
Expected: FAIL (no routes).

- [ ] **Step 6: Routes, controllers, views**

Inside `resources :businesses do`:

```ruby
    resources :mileage_entries, except: :show
```

Top level:

```ruby
  resources :tax_parameters, only: %i[index new create edit update]
```

`app/controllers/mileage_entries_controller.rb`:

```ruby
class MileageEntriesController < ApplicationController
  include BusinessScoped

  PERMITTED = %i[driven_on purpose from_location to_location miles round_trip].freeze

  before_action :require_editor!, except: :index
  before_action :set_entry, only: %i[edit update destroy]

  def index
    @year = (params[:year].presence || Date.current.year).to_i
    @entries = @business.mileage_entries.where(driven_on: Date.new(@year).all_year).order(:driven_on)
    @total_tenths = @entries.sum(&:effective_miles_tenths)
    @rate = TaxParameters.for_year(@year)
    @deduction_cents = @rate && MileageDeduction.cents(miles_tenths: @total_tenths, rate_tenth_cents: @rate.standard_mileage_rate_tenth_cents)
  end

  def new
    @entry = @business.mileage_entries.new(driven_on: Date.current)
  end

  def create
    @entry = @business.mileage_entries.new(params.expect(mileage_entry: PERMITTED))
    if @entry.save
      redirect_to business_mileage_entries_path(@business, year: @entry.driven_on.year), notice: "Trip logged."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @entry.update(params.expect(mileage_entry: PERMITTED))
      redirect_to business_mileage_entries_path(@business, year: @entry.driven_on.year), notice: "Trip updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy!
    redirect_to business_mileage_entries_path(@business, year: @entry.driven_on.year), notice: "Trip deleted.", status: :see_other
  end

  private

  def set_entry
    @entry = @business.mileage_entries.find(params[:id])
  end
end
```

`app/controllers/tax_parameters_controller.rb`:

```ruby
class TaxParametersController < ApplicationController
  before_action :require_household_owner!
  before_action :set_tax_parameters, only: %i[edit update]

  def index
    @all = TaxParameters.order(year: :desc)
  end

  def new
    @tax_parameters = TaxParameters.new(year: params[:year] || Date.current.year)
  end

  def create
    @tax_parameters = TaxParameters.new(params.expect(tax_parameter: %i[year mileage_rate_cents]))
    if @tax_parameters.save
      redirect_to tax_parameters_path, notice: "Saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @tax_parameters.update(params.expect(tax_parameter: %i[mileage_rate_cents]))
      redirect_to tax_parameters_path, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_tax_parameters
    @tax_parameters = TaxParameters.find(params[:id])
  end
end
```

`app/views/mileage_entries/index.html.erb`:

```erb
<%= business_nav @business %>
<h1>Mileage <%= @year %></h1>
<p class="no-print">
  <%= link_to "← #{@year - 1}", business_mileage_entries_path(@business, year: @year - 1) %>
  <%= link_to "#{@year + 1} →", business_mileage_entries_path(@business, year: @year + 1) %>
</p>
<% if @rate.nil? %>
  <p class="flash-alert">
    No IRS mileage rate is set for <%= @year %>.
    <%= Current.user.household_owner? ? link_to("Set it", new_tax_parameter_path(year: @year)) : "Ask the household owner to set it." %>
  </p>
<% end %>
<table>
  <thead><tr><th>Date</th><th>Purpose</th><th>From</th><th>To</th><th class="num">Miles</th><th></th></tr></thead>
  <tbody>
    <% @entries.each do |entry| %>
      <tr>
        <td><%= entry.driven_on %></td>
        <td><%= entry.purpose %></td>
        <td><%= entry.from_location %></td>
        <td><%= entry.to_location %></td>
        <td class="num"><%= Tenths.format(entry.effective_miles_tenths) %><%= " (round trip)" if entry.round_trip? %></td>
        <td><%= link_to "Edit", edit_business_mileage_entry_path(@business, entry) if current_membership.can_edit? %></td>
      </tr>
    <% end %>
  </tbody>
  <tfoot>
    <tr><th colspan="4">Total</th><th class="num"><%= Tenths.format(@total_tenths) %></th><th></th></tr>
    <% if @rate %>
      <tr><th colspan="4">Deduction at <%= Tenths.format(@rate.standard_mileage_rate_tenth_cents) %>¢/mile</th><th class="num"><%= money(@deduction_cents) %></th><th></th></tr>
    <% end %>
  </tfoot>
</table>
<%= link_to "Log a trip", new_business_mileage_entry_path(@business) if current_membership.can_edit? %>
```

`app/views/mileage_entries/_form.html.erb`:

```erb
<%= form_with model: [@business, entry] do |f| %>
  <%= render "shared/errors", record: entry %>
  <p><%= f.label :driven_on, "Date" %> <%= f.date_field :driven_on, required: true %></p>
  <p><%= f.label :purpose %> <%= f.text_field :purpose, required: true %></p>
  <p><%= f.label :from_location, "From" %> <%= f.text_field :from_location %></p>
  <p><%= f.label :to_location, "To" %> <%= f.text_field :to_location %></p>
  <p><%= f.label :miles, "Miles (one way)" %> <%= f.text_field :miles, size: 8, required: true %></p>
  <p><%= f.label :round_trip %> <%= f.check_box :round_trip %></p>
  <%= f.submit %>
<% end %>
<% if entry.persisted? %>
  <%= button_to "Delete", business_mileage_entry_path(@business, entry), method: :delete %>
<% end %>
```

`app/views/mileage_entries/new.html.erb`:

```erb
<%= business_nav @business %>
<h1>Log a trip</h1>
<%= render "form", entry: @entry %>
```

`app/views/mileage_entries/edit.html.erb`:

```erb
<%= business_nav @business %>
<h1>Edit trip</h1>
<%= render "form", entry: @entry %>
```

`app/views/tax_parameters/index.html.erb`:

```erb
<h1>Tax parameters</h1>
<table>
  <thead><tr><th>Year</th><th class="num">Mileage rate</th><th></th></tr></thead>
  <tbody>
    <% @all.each do |tp| %>
      <tr><td><%= tp.year %></td><td class="num"><%= tp.mileage_rate_cents %>¢</td><td><%= link_to "Edit", edit_tax_parameter_path(tp) %></td></tr>
    <% end %>
  </tbody>
</table>
<%= link_to "Add a year", new_tax_parameter_path %>
```

`app/views/tax_parameters/_form.html.erb`:

```erb
<%= form_with model: tax_parameters do |f| %>
  <%= render "shared/errors", record: tax_parameters %>
  <p><%= f.label :year %> <%= f.number_field :year, disabled: tax_parameters.persisted? %></p>
  <p><%= f.label :mileage_rate_cents, "IRS standard mileage rate (cents per mile)" %> <%= f.text_field :mileage_rate_cents, size: 6 %></p>
  <%= f.submit %>
<% end %>
```

`app/views/tax_parameters/new.html.erb`:

```erb
<h1>Add tax year</h1>
<%= render "form", tax_parameters: @tax_parameters %>
```

`app/views/tax_parameters/edit.html.erb`:

```erb
<h1>Edit <%= @tax_parameters.year %></h1>
<%= render "form", tax_parameters: @tax_parameters %>
```

Append to the business nav `<ul>`:

```erb
    <li><%= link_to "Mileage", business_mileage_entries_path(business) %></li>
```

In the layout `site-nav`, before "Sign out":

```erb
          <%= link_to "Tax parameters", tax_parameters_path if Current.user.household_owner? %>
```

- [ ] **Step 7: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add IRS mileage rate parameters and mileage log"
```

---

### Task 16: Report calculators and loaders

**Files:**
- Create: `app/models/reports/category_total.rb`, `app/models/reports/category_totals.rb`, `app/models/reports/mileage_totals.rb`, `app/models/reports/profit_and_loss.rb`, `app/models/reports/household_profit_and_loss.rb`, `app/models/reports/schedule_c_summary.rb`
- Test: `spec/models/reports/profit_and_loss_spec.rb`, `spec/models/reports/schedule_c_summary_spec.rb`, `spec/models/reports/household_profit_and_loss_spec.rb`, `spec/models/reports/loaders_spec.rb`

**Interfaces:**
- Consumes: `Transaction.countable`, `.for_businesses` (Task 9), `MileageEntry`, `TaxParameters`, `MileageDeduction` (Task 15), `ScheduleC` (Task 5)
- Produces:
  - `Reports::CategoryTotal` (`Data`: `business_id`, `category_id`, `name`, `kind`, `schedule_c_line`, `deductible_bps`, `sum_cents`)
  - `Reports::CategoryTotals.load(business_ids:, range:) → Array<CategoryTotal>` (countable, categorized, range inclusive)
  - `Reports::MileageTotal` (`Data`: `miles_tenths`, `deduction_cents`, `missing_rate_years`), `Reports::MileageTotals.load(business_ids:, range:)`
  - `Reports::ProfitAndLoss.new(category_totals:, mileage_deduction_cents:)`, with `#income_lines`, `#expense_lines` (each `Line(name, schedule_c_line, actual_cents, deductible_cents)`), `#total_income_cents`, `#total_expense_cents`, `#total_deductible_expense_cents`, `#mileage_deduction_cents`, `#net_profit_cents`
  - `Reports::HouseholdProfitAndLoss.new(by_business)` (Hash `Business => ProfitAndLoss`), with `#businesses`, `#income_rows`, `#expense_rows` (each `Row(name, amounts: {business_id => cents}, total_cents)`), `#column(:metric) → { business_id => cents, total: cents }`
  - `Reports::ScheduleCSummary.new(category_totals:, mileage_deduction_cents:)`, with `#lines → { "1" => cents, ... }` (in ScheduleC order, only lines with activity), `#gross_income_cents`, `#total_expenses_cents`, `#net_profit_cents`

- [ ] **Step 1: Write the failing pure specs**

`spec/models/reports/profit_and_loss_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Reports::ProfitAndLoss do
  def total(name, kind, sum, line: kind == "income" ? "1" : "18", bps: 10_000)
    Reports::CategoryTotal.new(business_id: 1, category_id: name.hash, name:, kind:, schedule_c_line: line, deductible_bps: bps, sum_cents: sum)
  end

  let(:report) do
    described_class.new(category_totals: [
      total("Sales", "income", 1_000_000),
      total("Refunds given", "income", -5_000, line: "2"),
      total("Office", "expense", -20_000),
      total("Meals", "expense", -3_333, line: "24b", bps: 5000),
      total("Software", "expense", 1_000)
    ], mileage_deduction_cents: 8_947)
  end

  it "keeps income signed" do
    expect(report.income_lines.map { [_1.name, _1.actual_cents] }).to eq([["Refunds given", -5_000], ["Sales", 1_000_000]])
    expect(report.total_income_cents).to eq(995_000)
  end

  it "shows expenses positive, with refunds reducing them" do
    expect(report.expense_lines.map { [_1.name, _1.actual_cents] }).to eq([["Meals", 3_333], ["Office", 20_000], ["Software", -1_000]])
  end

  it "applies deductible percentages, rounding half up once per line" do
    meals = report.expense_lines.find { _1.name == "Meals" }
    expect(meals.deductible_cents).to eq(1_667)
    expect(report.total_expense_cents).to eq(22_333)
    expect(report.total_deductible_expense_cents).to eq(20_667)
  end

  it "subtracts deductible expenses and mileage from income" do
    expect(report.net_profit_cents).to eq(995_000 - 20_667 - 8_947)
  end
end
```

`spec/models/reports/schedule_c_summary_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Reports::ScheduleCSummary do
  def total(name, kind, sum, line, bps: 10_000)
    Reports::CategoryTotal.new(business_id: 1, category_id: name.hash, name:, kind:, schedule_c_line: line, deductible_bps: bps, sum_cents: sum)
  end

  let(:summary) do
    described_class.new(category_totals: [
      total("Sales", "income", 500_000, "1"),
      total("Software", "expense", -10_000, "27a"),
      total("Phone", "expense", -5_000, "27a"),
      total("Meals", "expense", -2_001, "24b", bps: 5000),
      total("Parking", "expense", -1_500, "9")
    ], mileage_deduction_cents: 10_000)
  end

  it "groups by line in Schedule C order, combining mileage into line 9" do
    expect(summary.lines).to eq("1" => 500_000, "9" => 11_500, "24b" => 1_001, "27a" => 15_000)
  end

  it "totals" do
    expect(summary.gross_income_cents).to eq(500_000)
    expect(summary.total_expenses_cents).to eq(27_501)
    expect(summary.net_profit_cents).to eq(472_499)
  end

  it "adds a line 9 for mileage alone" do
    only_mileage = described_class.new(category_totals: [], mileage_deduction_cents: 500)
    expect(only_mileage.lines).to eq("9" => 500)
  end
end
```

`spec/models/reports/household_profit_and_loss_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Reports::HouseholdProfitAndLoss do
  FakeBusiness = Struct.new(:id, :name)

  def pnl(*totals, mileage: 0)
    Reports::ProfitAndLoss.new(category_totals: totals, mileage_deduction_cents: mileage)
  end

  def total(business_id, name, kind, sum)
    Reports::CategoryTotal.new(business_id:, category_id: 0, name:, kind:, schedule_c_line: kind == "income" ? "1" : "18", deductible_bps: 10_000, sum_cents: sum)
  end

  let(:pat) { FakeBusiness.new(1, "Pat") }
  let(:jordan) { FakeBusiness.new(2, "Jordan") }
  let(:report) do
    described_class.new(
      pat => pnl(total(1, "Sales", "income", 100_00), total(1, "Office", "expense", -10_00), mileage: 5_00),
      jordan => pnl(total(2, "Sales", "income", 50_00), total(2, "Supplies", "expense", -2_00))
    )
  end

  it "aligns rows by category name across businesses" do
    expect(report.income_rows.map { [_1.name, _1.amounts, _1.total_cents] }).to eq([["Sales", { 1 => 100_00, 2 => 50_00 }, 150_00]])
    expect(report.expense_rows.map { [_1.name, _1.amounts, _1.total_cents] }).to eq([
      ["Office", { 1 => 10_00 }, 10_00], ["Supplies", { 2 => 2_00 }, 2_00]
    ])
  end

  it "computes a summary column per business plus a total" do
    expect(report.column(:net_profit_cents)).to eq(1 => 85_00, 2 => 48_00, total: 133_00)
  end
end
```

Run: `bundle exec rspec spec/models/reports`
Expected: FAIL (`uninitialized constant Reports`).

- [ ] **Step 2: Implement the pure calculators**

`app/models/reports/category_total.rb`:

```ruby
module Reports
  CategoryTotal = Data.define(:business_id, :category_id, :name, :kind, :schedule_c_line, :deductible_bps, :sum_cents)
end
```

`app/models/reports/profit_and_loss.rb`:

```ruby
module Reports
  class ProfitAndLoss
    Line = Data.define(:name, :schedule_c_line, :actual_cents, :deductible_cents)

    attr_reader :mileage_deduction_cents

    def initialize(category_totals:, mileage_deduction_cents:)
      @totals = category_totals
      @mileage_deduction_cents = mileage_deduction_cents
    end

    def income_lines
      @income_lines ||= @totals.select { _1.kind == "income" }.map do |t|
        Line.new(name: t.name, schedule_c_line: t.schedule_c_line, actual_cents: t.sum_cents, deductible_cents: t.sum_cents)
      end.sort_by(&:name)
    end

    def expense_lines
      @expense_lines ||= @totals.select { _1.kind == "expense" }.map do |t|
        actual = -t.sum_cents
        Line.new(name: t.name, schedule_c_line: t.schedule_c_line, actual_cents: actual,
                 deductible_cents: Money.round_rational(Rational(actual * t.deductible_bps, 10_000)))
      end.sort_by(&:name)
    end

    def total_income_cents = income_lines.sum(&:actual_cents)
    def total_expense_cents = expense_lines.sum(&:actual_cents)
    def total_deductible_expense_cents = expense_lines.sum(&:deductible_cents)
    def net_profit_cents = total_income_cents - total_deductible_expense_cents - mileage_deduction_cents
  end
end
```

`app/models/reports/schedule_c_summary.rb`:

```ruby
module Reports
  class ScheduleCSummary
    def initialize(category_totals:, mileage_deduction_cents:)
      @pnl = ProfitAndLoss.new(category_totals:, mileage_deduction_cents:)
    end

    def lines
      @lines ||= begin
        amounts = Hash.new(0)
        @pnl.income_lines.each { amounts[_1.schedule_c_line] += _1.actual_cents }
        @pnl.expense_lines.each { amounts[_1.schedule_c_line] += _1.deductible_cents }
        amounts["9"] += @pnl.mileage_deduction_cents if @pnl.mileage_deduction_cents.positive?
        ScheduleC::LINES.keys.select { amounts.key?(_1) }.index_with { amounts[_1] }
      end
    end

    def gross_income_cents = lines.slice(*ScheduleC::INCOME_LINES).values.sum
    def total_expenses_cents = lines.except(*ScheduleC::INCOME_LINES).values.sum
    def net_profit_cents = gross_income_cents - total_expenses_cents
  end
end
```

`app/models/reports/household_profit_and_loss.rb`:

```ruby
module Reports
  class HouseholdProfitAndLoss
    Row = Data.define(:name, :amounts, :total_cents)

    def initialize(by_business)
      @by_business = by_business
    end

    def businesses = @by_business.keys

    def income_rows = rows(:income_lines)
    def expense_rows = rows(:expense_lines)

    def column(metric)
      values = @by_business.to_h { |business, pnl| [business.id, pnl.public_send(metric)] }
      values.merge(total: values.values.sum)
    end

    private

    def rows(kind)
      amounts = Hash.new { |h, k| h[k] = {} }
      @by_business.each do |business, pnl|
        pnl.public_send(kind).each { |line| amounts[line.name][business.id] = (amounts[line.name][business.id] || 0) + line.actual_cents }
      end
      amounts.keys.sort.map { |name| Row.new(name:, amounts: amounts[name], total_cents: amounts[name].values.sum) }
    end
  end
end
```

Run: `bundle exec rspec spec/models/reports`
Expected: PASS.

- [ ] **Step 3: Write the failing loader spec**

`spec/models/reports/loaders_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Report loaders" do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }
  let(:office) { create(:category, business: business, name: "Office") }
  let(:year) { Date.new(2026, 1, 1)..Date.new(2026, 12, 31) }

  describe Reports::CategoryTotals do
    it "sums countable categorized transactions in an inclusive range" do
      create(:transaction, account: account, category: office, amount_cents: -1_000, posted_on: Date.new(2026, 1, 1))
      create(:transaction, account: account, category: office, amount_cents: -2_000, posted_on: Date.new(2026, 12, 31))
      create(:transaction, account: account, category: office, amount_cents: 500, posted_on: Date.new(2026, 6, 1))
      create(:transaction, account: account, category: office, amount_cents: -9_999, posted_on: Date.new(2027, 1, 1))
      create(:transaction, account: account, category: office, amount_cents: -9_999, excluded: true)
      create(:transaction, account: account, amount_cents: -9_999, transfer: true)
      create(:transaction, account: account, amount_cents: -9_999)
      create(:transaction, amount_cents: -9_999)

      totals = Reports::CategoryTotals.load(business_ids: [business.id], range: year)
      expect(totals.map { [_1.business_id, _1.name, _1.kind, _1.sum_cents] }).to eq([[business.id, "Office", "expense", -2_500]])
    end
  end

  describe Reports::MileageTotals do
    it "values each year at its own rate and reports years without a rate" do
      create(:tax_parameters, year: 2026, standard_mileage_rate_tenth_cents: 725)
      create(:mileage_entry, business: business, driven_on: Date.new(2026, 12, 31), miles_tenths: 617, round_trip: true)
      create(:mileage_entry, business: business, driven_on: Date.new(2027, 1, 1), miles_tenths: 100)

      result = Reports::MileageTotals.load(business_ids: [business.id], range: Date.new(2026, 1, 1)..Date.new(2027, 12, 31))
      expect(result.miles_tenths).to eq(1334)
      expect(result.deduction_cents).to eq(8_947)
      expect(result.missing_rate_years).to eq([2027])
    end
  end
end
```

Run: `bundle exec rspec spec/models/reports/loaders_spec.rb`
Expected: FAIL (`uninitialized constant Reports::CategoryTotals`).

- [ ] **Step 4: Implement the loaders**

`app/models/reports/category_totals.rb`:

```ruby
module Reports
  module CategoryTotals
    COLUMNS = %w[accounts.business_id categories.id categories.name categories.kind categories.schedule_c_line categories.deductible_bps].freeze

    def self.load(business_ids:, range:)
      Transaction.countable.for_businesses(business_ids).where(posted_on: range).joins(:category)
        .group(*COLUMNS).sum("transactions.amount_cents")
        .map do |(business_id, category_id, name, kind, line, bps), sum|
          CategoryTotal.new(business_id:, category_id:, name:, kind:, schedule_c_line: line, deductible_bps: bps, sum_cents: sum)
        end
    end
  end
end
```

`app/models/reports/mileage_totals.rb`:

```ruby
module Reports
  MileageTotal = Data.define(:miles_tenths, :deduction_cents, :missing_rate_years)

  module MileageTotals
    def self.load(business_ids:, range:)
      by_year = MileageEntry.where(business_id: business_ids, driven_on: range).group_by { _1.driven_on.year }
      rates = TaxParameters.where(year: by_year.keys).pluck(:year, :standard_mileage_rate_tenth_cents).to_h

      tenths = 0
      deduction = 0
      missing = []
      by_year.sort.each do |year, entries|
        year_tenths = entries.sum(&:effective_miles_tenths)
        tenths += year_tenths
        if rates[year]
          deduction += MileageDeduction.cents(miles_tenths: year_tenths, rate_tenth_cents: rates[year])
        else
          missing << year
        end
      end
      MileageTotal.new(miles_tenths: tenths, deduction_cents: deduction, missing_rate_years: missing)
    end
  end
end
```

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add P&L, Schedule C, and household report calculators"
```

---

### Task 17: Report screens and CSV exports

**Files:**
- Create: `app/controllers/concerns/date_range_params.rb`; `app/models/reports/csv_safe.rb`, `app/models/reports/transaction_csv.rb`, `app/models/reports/mileage_log_csv.rb`; controllers `profit_and_losses_controller.rb`, `schedule_cs_controller.rb`, `mileage_logs_controller.rb`, `transaction_exports_controller.rb`, `household_profit_and_losses_controller.rb`, `household_transaction_exports_controller.rb`; views `profit_and_losses/show`, `schedule_cs/show`, `mileage_logs/show`, `household_profit_and_losses/show`, `shared/_date_range_form`
- Modify: `config/routes.rb`, `app/views/businesses/_nav.html.erb`, `app/views/layouts/application.html.erb`
- Test: `spec/models/reports/csv_spec.rb`, `spec/requests/reports_spec.rb`

**Interfaces:**
- Consumes: everything in Task 16, `require_household_access!` (Task 6)
- Produces:
  - `DateRangeParams#date_range → Range<Date>` (params `from`/`to`, ISO; defaults Jan 1 of this year..today)
  - `Reports::CsvSafe.text(value)`: prefixes `'` when a text cell starts with `=`, `+`, `-`, `@`, tab, or CR (spreadsheet formula injection)
  - `Reports::TransactionCsv.generate(transactions) → String`, `Reports::MileageLogCsv.generate(entries, rate_tenth_cents:) → String`
  - Routes: `business_profit_and_loss_path(b, from:, to:)`, `business_schedule_c_path(b, year:)`, `business_mileage_log_path(b, year:, format: :csv)`, `business_transaction_export_path(b, from:, to:, format: :csv)`, `household_profit_and_loss_path`, `household_transaction_export_path(format: :csv)`

- [ ] **Step 1: Write the failing CSV spec**

`spec/models/reports/csv_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Report CSVs" do
  let(:business) { create(:business, name: "Pat Consulting") }
  let(:account) { create(:account, business: business, name: "Checking") }
  let(:meals) { create(:category, business: business, name: "Meals", schedule_c_line: "24b", deductible_bps: 5000) }

  describe Reports::CsvSafe do
    it "neutralizes formula-looking text" do
      expect(Reports::CsvSafe.text("=HYPERLINK(1)")).to eq("'=HYPERLINK(1)")
      expect(Reports::CsvSafe.text("@SUM")).to eq("'@SUM")
      expect(Reports::CsvSafe.text("Coffee")).to eq("Coffee")
      expect(Reports::CsvSafe.text(nil)).to be_nil
    end
  end

  describe Reports::TransactionCsv do
    it "writes one row per transaction with deductible amounts" do
      create(:transaction, account: account, category: meals, payee: "=cmd", amount_cents: -3_333, posted_on: Date.new(2026, 2, 1))
      rows = CSV.parse(Reports::TransactionCsv.generate(Transaction.includes(:category, account: :business)))
      expect(rows.first).to eq(Reports::TransactionCsv::HEADERS)
      expect(rows.second).to eq(["2026-02-01", "Pat Consulting", "Checking", "'=cmd", nil, "-33.33", "Meals", "24b", "no", "16.67"])
    end
  end

  describe Reports::MileageLogCsv do
    it "writes entries, a total, and the deduction" do
      entry = create(:mileage_entry, business: business, miles_tenths: 1234, driven_on: Date.new(2026, 3, 2))
      rows = CSV.parse(Reports::MileageLogCsv.generate([entry], rate_tenth_cents: 725))
      expect(rows[1]).to eq(["2026-03-02", "Client meeting", "Home office", "Client", "123.4", "no"])
      expect(rows[-2]).to eq(["Total", nil, nil, nil, "123.4", nil])
      expect(rows[-1]).to eq(["Deduction at 72.5¢/mile", nil, nil, nil, "89.47", nil])
    end

    it "omits the deduction row without a rate" do
      rows = CSV.parse(Reports::MileageLogCsv.generate([], rate_tenth_cents: nil))
      expect(rows.last.first).to eq("Total")
    end
  end
end
```

Run: `bundle exec rspec spec/models/reports/csv_spec.rb`
Expected: FAIL (`uninitialized constant Reports::CsvSafe`).

- [ ] **Step 2: Implement the CSV writers**

`app/models/reports/csv_safe.rb`:

```ruby
module Reports
  module CsvSafe
    DANGEROUS = /\A[=+\-@\t\r]/

    def self.text(value)
      return value if value.nil?

      value.to_s.match?(DANGEROUS) ? "'#{value}" : value.to_s
    end
  end
end
```

`app/models/reports/transaction_csv.rb`:

```ruby
require "csv"

module Reports
  module TransactionCsv
    HEADERS = ["Date", "Business", "Account", "Payee", "Memo", "Amount", "Category", "Schedule C line", "Transfer", "Deductible amount"].freeze

    def self.generate(transactions)
      CSV.generate do |csv|
        csv << HEADERS
        transactions.each do |txn|
          category = txn.category
          deductible =
            if category&.expense? then Money.round_rational(Rational(-txn.amount_cents * category.deductible_bps, 10_000))
            elsif category&.income? then txn.amount_cents
            end
          csv << [
            txn.posted_on.iso8601, CsvSafe.text(txn.account.business.name), CsvSafe.text(txn.account.name),
            CsvSafe.text(txn.payee), CsvSafe.text(txn.memo), Money.new(txn.amount_cents).to_input,
            CsvSafe.text(category&.name), category&.schedule_c_line, txn.transfer? ? "yes" : "no",
            deductible && Money.new(deductible).to_input
          ]
        end
      end
    end
  end
end
```

`app/models/reports/mileage_log_csv.rb`:

```ruby
require "csv"

module Reports
  module MileageLogCsv
    HEADERS = ["Date", "Purpose", "From", "To", "Miles", "Round trip"].freeze

    def self.generate(entries, rate_tenth_cents:)
      total = entries.sum(&:effective_miles_tenths)
      CSV.generate do |csv|
        csv << HEADERS
        entries.each do |e|
          csv << [e.driven_on.iso8601, CsvSafe.text(e.purpose), CsvSafe.text(e.from_location), CsvSafe.text(e.to_location),
                  Tenths.format(e.effective_miles_tenths), e.round_trip? ? "yes" : "no"]
        end
        csv << ["Total", nil, nil, nil, Tenths.format(total), nil]
        if rate_tenth_cents
          deduction = MileageDeduction.cents(miles_tenths: total, rate_tenth_cents: rate_tenth_cents)
          csv << ["Deduction at #{Tenths.format(rate_tenth_cents)}¢/mile", nil, nil, nil, Money.new(deduction).to_input, nil]
        end
      end
    end
  end
end
```

Run: `bundle exec rspec spec/models/reports/csv_spec.rb`
Expected: PASS.

- [ ] **Step 3: Write the failing request spec**

`spec/requests/reports_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Reports" do
  let!(:household) { create(:household) }
  let!(:pat) { create(:business, name: "Pat Consulting") }
  let!(:jordan) { create(:business, name: "Jordan Studio") }
  let!(:sales) { create(:category, :income, business: pat, name: "Sales") }
  let!(:account) { create(:account, business: pat) }
  let!(:rate) { create(:tax_parameters, year: 2026, standard_mileage_rate_tenth_cents: 725) }

  before do
    create(:transaction, account: account, category: sales, amount_cents: 1_234_500, posted_on: Date.new(2026, 3, 1))
    create(:mileage_entry, business: pat, miles_tenths: 1234, driven_on: Date.new(2026, 3, 2))
  end

  let(:accountant) do
    create(:user).tap do |u|
      create(:membership, user: u, business: pat, role: "viewer")
      create(:membership, user: u, business: jordan, role: "viewer")
    end
  end

  it "shows a business P&L for a date range" do
    sign_in_as accountant
    get business_profit_and_loss_path(pat, from: "2026-01-01", to: "2026-12-31")
    expect(response.body).to include("$12,345.00")
    expect(response.body).to include("$89.47")
  end

  it "shows Schedule C with mileage on line 9" do
    sign_in_as accountant
    get business_schedule_c_path(pat, year: 2026)
    expect(response.body).to include("Line 9: Car and truck expenses")
    expect(response.body).to include("$12,255.53")
  end

  it "exports the mileage log and transactions as CSV" do
    sign_in_as accountant
    get business_mileage_log_path(pat, year: 2026, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("123.4")
    get business_transaction_export_path(pat, from: "2026-01-01", to: "2026-12-31", format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(CSV.parse(response.body).size).to eq(2)
  end

  it "shows the household P&L to someone who can see every business" do
    sign_in_as accountant
    get household_profit_and_loss_path(from: "2026-01-01", to: "2026-12-31")
    expect(response.body).to include("Pat Consulting")
    expect(response.body).to include("Jordan Studio")
    get household_transaction_export_path(format: :csv, from: "2026-01-01", to: "2026-12-31")
    expect(response).to have_http_status(:ok)
  end

  it "hides household reports from someone missing a business" do
    sign_in_as user_with_role("owner", pat)
    get household_profit_and_loss_path
    expect(response).to have_http_status(:not_found)
    get household_transaction_export_path(format: :csv)
    expect(response).to have_http_status(:not_found)
  end

  it "is not found for non-members" do
    sign_in_as user_with_role("owner", jordan)
    get business_profit_and_loss_path(pat)
    expect(response).to have_http_status(:not_found)
  end
end
```

(Schedule C check: line 1 = $12,345.00, line 9 = $89.47, so net profit = $12,255.53.)

Run: `bundle exec rspec spec/requests/reports_spec.rb`
Expected: FAIL (no routes).

- [ ] **Step 4: Routes, concern, controllers**

Inside `resources :businesses do`:

```ruby
    get "reports/profit_and_loss", to: "profit_and_losses#show", as: :profit_and_loss
    get "reports/schedule_c", to: "schedule_cs#show", as: :schedule_c
    get "reports/mileage_log", to: "mileage_logs#show", as: :mileage_log
    get "reports/transactions", to: "transaction_exports#show", as: :transaction_export
```

Top level:

```ruby
  scope "household", as: "household" do
    get "profit_and_loss", to: "household_profit_and_losses#show", as: :profit_and_loss
    get "transactions", to: "household_transaction_exports#show", as: :transaction_export
  end
```

`app/controllers/concerns/date_range_params.rb`:

```ruby
module DateRangeParams
  extend ActiveSupport::Concern

  included do
    helper_method :date_range
  end

  private

  def date_range
    @date_range ||= (parse_date(params[:from]) || Date.current.beginning_of_year)..(parse_date(params[:to]) || Date.current)
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end
end
```

`app/controllers/profit_and_losses_controller.rb`:

```ruby
class ProfitAndLossesController < ApplicationController
  include BusinessScoped
  include DateRangeParams

  def show
    @mileage = Reports::MileageTotals.load(business_ids: [@business.id], range: date_range)
    @report = Reports::ProfitAndLoss.new(
      category_totals: Reports::CategoryTotals.load(business_ids: [@business.id], range: date_range),
      mileage_deduction_cents: @mileage.deduction_cents
    )
  end
end
```

`app/controllers/schedule_cs_controller.rb`:

```ruby
class ScheduleCsController < ApplicationController
  include BusinessScoped

  def show
    @year = (params[:year].presence || Date.current.year).to_i
    range = Date.new(@year).all_year
    @mileage = Reports::MileageTotals.load(business_ids: [@business.id], range: range)
    @summary = Reports::ScheduleCSummary.new(
      category_totals: Reports::CategoryTotals.load(business_ids: [@business.id], range: range),
      mileage_deduction_cents: @mileage.deduction_cents
    )
  end
end
```

`app/controllers/mileage_logs_controller.rb`:

```ruby
class MileageLogsController < ApplicationController
  include BusinessScoped

  def show
    year = (params[:year].presence || Date.current.year).to_i
    entries = @business.mileage_entries.where(driven_on: Date.new(year).all_year).order(:driven_on)
    rate = TaxParameters.for_year(year)&.standard_mileage_rate_tenth_cents
    send_data Reports::MileageLogCsv.generate(entries, rate_tenth_cents: rate),
      filename: "#{@business.name.parameterize}-mileage-#{year}.csv", type: "text/csv"
  end
end
```

`app/controllers/transaction_exports_controller.rb`:

```ruby
class TransactionExportsController < ApplicationController
  include BusinessScoped
  include DateRangeParams

  def show
    transactions = Transaction.for_businesses(@business.id).where(excluded: false, posted_on: date_range)
      .includes(:category, account: :business).order(:posted_on, :id)
    send_data Reports::TransactionCsv.generate(transactions),
      filename: "#{@business.name.parameterize}-transactions-#{date_range.first}-#{date_range.last}.csv", type: "text/csv"
  end
end
```

`app/controllers/household_profit_and_losses_controller.rb`:

```ruby
class HouseholdProfitAndLossesController < ApplicationController
  include DateRangeParams

  before_action :require_household_access!

  def show
    @report = Reports::HouseholdProfitAndLoss.new(
      Business.active.order(:name).to_h do |business|
        mileage = Reports::MileageTotals.load(business_ids: [business.id], range: date_range)
        [business, Reports::ProfitAndLoss.new(
          category_totals: Reports::CategoryTotals.load(business_ids: [business.id], range: date_range),
          mileage_deduction_cents: mileage.deduction_cents
        )]
      end
    )
  end
end
```

`app/controllers/household_transaction_exports_controller.rb`:

```ruby
class HouseholdTransactionExportsController < ApplicationController
  include DateRangeParams

  before_action :require_household_access!

  def show
    transactions = Transaction.for_businesses(Business.select(:id)).where(excluded: false, posted_on: date_range)
      .includes(:category, account: :business).order(:posted_on, :id)
    send_data Reports::TransactionCsv.generate(transactions),
      filename: "household-transactions-#{date_range.first}-#{date_range.last}.csv", type: "text/csv"
  end
end
```

- [ ] **Step 5: Views**

`app/views/shared/_date_range_form.html.erb` (local: `url`):

```erb
<%= form_with url: url, method: :get, class: "inline-form no-print" do |f| %>
  <%= f.date_field :from, value: date_range.first %>
  <%= f.date_field :to, value: date_range.last %>
  <%= f.submit "Update" %>
<% end %>
```

`app/views/profit_and_losses/show.html.erb`:

```erb
<%= business_nav @business %>
<h1>Profit &amp; loss</h1>
<%= render "shared/date_range_form", url: business_profit_and_loss_path(@business) %>
<% if @mileage.missing_rate_years.any? %>
  <p class="flash-alert">Mileage for <%= @mileage.missing_rate_years.to_sentence %> is excluded: no IRS rate set.</p>
<% end %>
<table>
  <thead><tr><th>Category</th><th class="num">Actual</th><th class="num">Deductible</th></tr></thead>
  <tbody>
    <tr><th colspan="3">Income</th></tr>
    <% @report.income_lines.each do |line| %>
      <tr><td><%= line.name %></td><td class="num"><%= money(line.actual_cents) %></td><td class="num"><%= money(line.deductible_cents) %></td></tr>
    <% end %>
    <tr><th>Total income</th><th class="num"><%= money(@report.total_income_cents) %></th><th class="num"><%= money(@report.total_income_cents) %></th></tr>
    <tr><th colspan="3">Expenses</th></tr>
    <% @report.expense_lines.each do |line| %>
      <tr><td><%= line.name %></td><td class="num"><%= money(line.actual_cents) %></td><td class="num"><%= money(line.deductible_cents) %></td></tr>
    <% end %>
    <tr><td>Mileage deduction</td><td class="num">—</td><td class="num"><%= money(@report.mileage_deduction_cents) %></td></tr>
    <tr><th>Total expenses</th><th class="num"><%= money(@report.total_expense_cents) %></th><th class="num"><%= money(@report.total_deductible_expense_cents + @report.mileage_deduction_cents) %></th></tr>
    <tr><th>Net profit (tax basis)</th><th></th><th class="num"><%= money(@report.net_profit_cents) %></th></tr>
  </tbody>
</table>
<p class="no-print"><%= link_to "Export transactions (CSV)", business_transaction_export_path(@business, from: date_range.first, to: date_range.last, format: :csv) %></p>
```

`app/views/schedule_cs/show.html.erb`:

```erb
<%= business_nav @business %>
<h1>Schedule C summary <%= @year %></h1>
<p class="no-print">
  <%= link_to "← #{@year - 1}", business_schedule_c_path(@business, year: @year - 1) %>
  <%= link_to "#{@year + 1} →", business_schedule_c_path(@business, year: @year + 1) %>
</p>
<% if @mileage.missing_rate_years.any? %>
  <p class="flash-alert">Mileage is excluded: no IRS rate set for <%= @year %>.</p>
<% end %>
<table>
  <tbody>
    <% @summary.lines.each do |code, cents| %>
      <tr><td><%= ScheduleC.label(code) %></td><td class="num"><%= money(cents) %></td></tr>
    <% end %>
    <tr><td><%= ScheduleC.label("30") %></td><td class="num">—</td></tr>
    <tr><th>Gross income</th><th class="num"><%= money(@summary.gross_income_cents) %></th></tr>
    <tr><th>Total expenses</th><th class="num"><%= money(@summary.total_expenses_cents) %></th></tr>
    <tr><th>Net profit</th><th class="num"><%= money(@summary.net_profit_cents) %></th></tr>
  </tbody>
</table>
<p class="no-print"><%= link_to "Mileage log (CSV)", business_mileage_log_path(@business, year: @year, format: :csv) %></p>
```

`app/views/household_profit_and_losses/show.html.erb`:

```erb
<h1>Household profit &amp; loss</h1>
<%= render "shared/date_range_form", url: household_profit_and_loss_path %>
<% businesses = @report.businesses %>
<table>
  <thead>
    <tr><th></th><% businesses.each do |b| %><th class="num"><%= b.name %></th><% end %><th class="num">Total</th></tr>
  </thead>
  <tbody>
    <% [["Income", @report.income_rows], ["Expenses", @report.expense_rows]].each do |heading, rows| %>
      <tr><th colspan="<%= businesses.size + 2 %>"><%= heading %></th></tr>
      <% rows.each do |row| %>
        <tr>
          <td><%= row.name %></td>
          <% businesses.each do |b| %><td class="num"><%= money(row.amounts[b.id]) %></td><% end %>
          <td class="num"><%= money(row.total_cents) %></td>
        </tr>
      <% end %>
    <% end %>
    <% [["Mileage deduction", :mileage_deduction_cents], ["Net profit (tax basis)", :net_profit_cents]].each do |label, metric| %>
      <% column = @report.column(metric) %>
      <tr>
        <th><%= label %></th>
        <% businesses.each do |b| %><th class="num"><%= money(column[b.id]) %></th><% end %>
        <th class="num"><%= money(column[:total]) %></th>
      </tr>
    <% end %>
  </tbody>
</table>
<p class="no-print"><%= link_to "Export household transactions (CSV)", household_transaction_export_path(from: date_range.first, to: date_range.last, format: :csv) %></p>
```

Append to the business nav `<ul>`:

```erb
    <li><%= link_to "P&L", business_profit_and_loss_path(business) %></li>
    <li><%= link_to "Schedule C", business_schedule_c_path(business) %></li>
```

In the layout `site-nav`, after "Inbox":

```erb
          <%= link_to "Household", household_profit_and_loss_path if Current.user.can_view_household? %>
```

- [ ] **Step 6: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add P&L, Schedule C, household, and CSV export reports"
```

---

### Task 18: Invite links, members, and people

**Files:**
- Create: migrations `create_invites`, `create_invite_grants`; `app/models/invite.rb`, `app/models/invite_grant.rb`; `app/controllers/invites_controller.rb`, `app/controllers/invite_acceptances_controller.rb`, `app/controllers/memberships_controller.rb`, `app/controllers/people_controller.rb`; views for each; `spec/factories/invites.rb`
- Modify: `app/models/membership.rb`, `config/routes.rb`, `app/views/businesses/_nav.html.erb`, `app/views/layouts/application.html.erb`
- Test: `spec/models/invite_spec.rb`, `spec/requests/invites_spec.rb`, `spec/requests/memberships_spec.rb`, `spec/requests/people_spec.rb`, `spec/system/invite_spec.rb`

**Interfaces:**
- Consumes: `begin_two_factor` (Task 3), `Membership::RANK` (Task 4)
- Produces:
  - `Invite` (`created_by`, `email`, `token_digest`, `expires_at`, `accepted_at`, `accepted_by`, `grants`), `Invite::TTL = 7.days`, `Invite::AlreadyUsed`, `#token` (plain token, only on the instance that created it), `#grant_roles=(Hash business_id => role)`, `Invite.find_usable(token)`, `#accept!(user)` (single use, upgrades roles but never downgrades)
  - `InviteGrant` (`invite`, `business`, `role`)
  - `Membership#last_owner?`
  - Routes: `invites_path`, `new_invite_path`, `join_path(token)` (GET/POST), `business_memberships_path(b)`, `business_membership_path(b, m)`, `people_path`, `new_person_path`, `edit_person_path(p)`

- [ ] **Step 1: Migrations**

```bash
bin/rails generate migration CreateInvites
bin/rails generate migration CreateInviteGrants
```

```ruby
class CreateInvites < ActiveRecord::Migration[8.1]
  def change
    create_table :invites do |t|
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :email
      t.string :token_digest, null: false, index: { unique: true }
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
```

```ruby
class CreateInviteGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :invite_grants do |t|
      t.references :invite, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Factory**

`spec/factories/invites.rb`:

```ruby
FactoryBot.define do
  factory :invite do
    association :created_by, factory: [:user, :household_owner]
    transient do
      business { association :business }
      role { "viewer" }
    end
    after(:build) { |invite, ctx| invite.grant_roles = { ctx.business.id.to_s => ctx.role } }
  end
end
```

- [ ] **Step 3: Write the failing model spec**

`spec/models/invite_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Invite do
  let(:business) { create(:business) }

  it "stores only a digest of the token and expires in 7 days" do
    invite = create(:invite, business: business)
    expect(invite.token).to be_present
    expect(invite.token_digest).to eq(Invite.digest(invite.token))
    expect(invite.expires_at).to be_within(1.minute).of(7.days.from_now)
    expect(Invite.find_usable(invite.token)).to eq(invite)
  end

  it "is not usable after it expires or is accepted" do
    invite = create(:invite, business: business)
    travel 8.days
    expect(Invite.find_usable(invite.token)).to be_nil
  end

  it "requires at least one grant" do
    invite = Invite.new(created_by: create(:user, :household_owner))
    expect(invite).not_to be_valid
    expect(invite.errors[:base]).to include("Grant access to at least one business")
  end

  it "only lets creators grant businesses they own" do
    editor = user_with_role("editor", business)
    invite = Invite.new(created_by: editor)
    invite.grant_roles = { business.id.to_s => "viewer" }
    expect(invite).not_to be_valid
    owner = user_with_role("owner", business)
    invite = Invite.new(created_by: owner)
    invite.grant_roles = { business.id.to_s => "viewer" }
    expect(invite).to be_valid
  end

  it "ignores blank roles and rejects unknown ones" do
    invite = Invite.new(created_by: create(:user, :household_owner))
    invite.grant_roles = { business.id.to_s => "", create(:business).id.to_s => "admin" }
    expect(invite.grants.size).to eq(1)
    expect(invite).not_to be_valid
  end

  describe "#accept!" do
    let(:invite) { create(:invite, business: business, role: "editor") }
    let(:user) { create(:user) }

    it "grants memberships once" do
      invite.accept!(user)
      expect(user.membership_for(business)).to be_editor
      expect(invite.reload.accepted_by).to eq(user)
      expect { invite.accept!(create(:user)) }.to raise_error(Invite::AlreadyUsed)
    end

    it "upgrades but never downgrades" do
      create(:membership, user: user, business: business, role: "owner")
      invite.accept!(user)
      expect(user.membership_for(business)).to be_owner
    end
  end
end
```

Run: `bundle exec rspec spec/models/invite_spec.rb`
Expected: FAIL (`uninitialized constant Invite`).

- [ ] **Step 4: Implement the models**

`app/models/invite_grant.rb`:

```ruby
class InviteGrant < ApplicationRecord
  belongs_to :invite
  belongs_to :business

  validates :role, inclusion: { in: Membership::RANK.keys }
end
```

`app/models/invite.rb`:

```ruby
class Invite < ApplicationRecord
  TTL = 7.days

  class AlreadyUsed < StandardError; end

  belongs_to :created_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true
  has_many :grants, class_name: "InviteGrant", dependent: :destroy, inverse_of: :invite

  attr_reader :token

  scope :usable, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :has_grants
  validate :creator_may_grant

  before_validation :generate_token, on: :create

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.find_usable(token) = usable.find_by(token_digest: digest(token))

  def grant_roles=(roles)
    roles.to_h.each do |business_id, role|
      next if role.blank?

      grants.build(business: Business.find(business_id), role: role)
    end
  end

  def accept!(user)
    ApplicationRecord.transaction do
      claimed = Invite.usable.where(id: id).update_all(accepted_at: Time.current, accepted_by_id: user.id)
      raise AlreadyUsed, "This invite has already been used or has expired." if claimed.zero?

      grants.includes(:business).each do |grant|
        membership = user.memberships.find_or_initialize_by(business: grant.business)
        if membership.new_record? || Membership::RANK[grant.role] > Membership::RANK[membership.role]
          membership.role = grant.role
        end
        membership.save!
      end
    end
    reload
  end

  private

  def generate_token
    @token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest(@token)
    self.expires_at ||= TTL.from_now
  end

  def has_grants
    errors.add(:base, "Grant access to at least one business") if grants.empty?
  end

  def creator_may_grant
    return if created_by.nil? || created_by.household_owner?
    return if grants.all? { |grant| created_by.membership_for(grant.business)&.owner? }

    errors.add(:base, "You can only grant access to businesses you own")
  end
end
```

Add to `app/models/membership.rb`:

```ruby
  def last_owner? = owner? && business.memberships.owner.where.not(id: id).none?
```

Run: `bundle exec rspec spec/models/invite_spec.rb`
Expected: PASS.

- [ ] **Step 5: Write failing request and system specs**

`spec/requests/invites_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Invites" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:other) { create(:business, name: "Jordan Studio") }

  it "lets a business owner create an invite and see the link once" do
    sign_in_as user_with_role("owner", business)
    post invites_path, params: { invite: { email: "acct@example.com", grant_roles: { business.id => "viewer" } } }
    expect(response).to have_http_status(:created)
    expect(response.body).to match(%r{/join/[\w-]{20,}})
  end

  it "rejects granting a business the creator doesn't own" do
    sign_in_as user_with_role("owner", business)
    post invites_path, params: { invite: { grant_roles: { other.id => "viewer" } } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "forbids users who own nothing" do
    sign_in_as user_with_role("editor", business)
    get new_invite_path
    expect(response).to have_http_status(:forbidden)
  end

  describe "accepting" do
    let(:invite) { create(:invite, business: business, role: "viewer", email: "new@example.com") }

    it "signs up a new user, grants access, and starts 2FA enrollment" do
      post join_path(invite.token), params: { user: {
        name: "Avery", email_address: "new@example.com", password: AuthHelpers::PASSWORD, password_confirmation: AuthHelpers::PASSWORD
      } }
      expect(response).to redirect_to(new_two_factor_setup_path)
      expect(User.find_by!(email_address: "new@example.com").membership_for(business)).to be_viewer
    end

    it "re-renders signup errors without consuming the invite" do
      post join_path(invite.token), params: { user: { name: "A", email_address: "new@example.com", password: "short", password_confirmation: "short" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Invite.find_usable(invite.token)).to eq(invite)
    end

    it "adds access for a signed-in user" do
      user = create(:user)
      sign_in_as user
      post join_path(invite.token)
      expect(response).to redirect_to(root_path)
      expect(user.membership_for(business)).to be_viewer
    end

    it "shows not found for used or expired tokens" do
      invite.accept!(create(:user))
      get join_path(invite.token)
      expect(response).to have_http_status(:not_found)
      get join_path("nonsense")
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

`spec/requests/memberships_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Memberships" do
  let!(:business) { create(:business) }
  let!(:owner) { user_with_role("owner", business) }

  it "lets owners change roles" do
    member = user_with_role("viewer", business)
    sign_in_as owner
    patch business_membership_path(business, member.membership_for(business)), params: { membership: { role: "editor" } }
    expect(member.membership_for(business)).to be_editor
  end

  it "refuses to demote or remove the last owner" do
    sign_in_as owner
    membership = owner.membership_for(business)
    patch business_membership_path(business, membership), params: { membership: { role: "viewer" } }
    expect(membership.reload).to be_owner
    delete business_membership_path(business, membership)
    expect(Membership.exists?(membership.id)).to be(true)
    expect(flash[:alert]).to eq("A business needs at least one owner.")
  end

  it "removes members" do
    member = user_with_role("viewer", business)
    sign_in_as owner
    delete business_membership_path(business, member.membership_for(business))
    expect(member.membership_for(business)).to be_nil
  end

  it "forbids non-owners" do
    sign_in_as user_with_role("editor", business)
    get business_memberships_path(business)
    expect(response).to have_http_status(:forbidden)
  end
end
```

`spec/requests/people_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "People" do
  let!(:household) { create(:household) }
  let!(:spouse) { create(:person, household: household, name: "Jordan") }
  let(:household_owner) { create(:user, :household_owner) }

  it "lets the household owner link a user to a person" do
    jordan_user = create(:user, name: "Jordan")
    sign_in_as household_owner
    patch person_path(spouse), params: { person: { name: "Jordan", user_id: jordan_user.id } }
    expect(spouse.reload.user).to eq(jordan_user)
  end

  it "refuses a third person" do
    create(:person, household: household)
    sign_in_as household_owner
    post people_path, params: { person: { name: "Third" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "forbids others" do
    sign_in_as create(:user)
    get people_path
    expect(response).to have_http_status(:forbidden)
  end
end
```

`spec/system/invite_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Inviting the accountant" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:owner) { user_with_role("owner", business) }

  it "creates a link that a new user can join with" do
    system_sign_in_as owner
    visit new_invite_path
    fill_in "Email (optional)", with: "acct@example.com"
    select "Viewer", from: "Pat Consulting"
    click_on "Create invite"
    join_url = find("#join-url").text
    click_on "Sign out"

    visit URI(join_url).path
    fill_in "Name", with: "Avery Accountant"
    fill_in "Password", with: AuthHelpers::PASSWORD
    fill_in "Password confirmation", with: AuthHelpers::PASSWORD
    click_on "Join"
    expect(page).to have_content("Set up two-factor authentication")
  end
end
```

Run: `bundle exec rspec spec/requests/invites_spec.rb spec/requests/memberships_spec.rb spec/requests/people_spec.rb spec/system/invite_spec.rb`
Expected: FAIL (no routes).

- [ ] **Step 6: Routes and controllers**

Inside `resources :businesses do`:

```ruby
    resources :memberships, only: %i[index update destroy]
```

Top level:

```ruby
  resources :invites, only: %i[index new create]
  get "join/:token", to: "invite_acceptances#show", as: :join
  post "join/:token", to: "invite_acceptances#create"
  resources :people, only: %i[index new create edit update]
```

`app/controllers/invites_controller.rb`:

```ruby
class InvitesController < ApplicationController
  before_action :require_inviter!

  def index
    scope = Current.user.household_owner? ? Invite.all : Invite.where(created_by: Current.user)
    @invites = scope.includes(:accepted_by, grants: :business).order(created_at: :desc)
  end

  def new
    @invite = Invite.new
    @grantable = grantable_businesses
  end

  def create
    @invite = Invite.new(created_by: Current.user, email: params.dig(:invite, :email))
    @invite.grant_roles = params.dig(:invite, :grant_roles)&.to_unsafe_h || {}
    if @invite.save
      @join_url = join_url(@invite.token)
      render :show, status: :created
    else
      @grantable = grantable_businesses
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    head :unprocessable_entity
  end

  private

  def require_inviter!
    head :forbidden unless Current.user.household_owner? || Current.user.memberships.owner.exists?
  end

  def grantable_businesses
    return Business.active.order(:name) if Current.user.household_owner?

    Business.active.where(id: Current.user.memberships.owner.select(:business_id)).order(:name)
  end
end
```

(Grant values are validated by `InviteGrant` role inclusion and `Invite#creator_may_grant`; unknown business ids raise `RecordNotFound` → 422.)

`app/controllers/invite_acceptances_controller.rb`:

```ruby
class InviteAcceptancesController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  before_action :set_invite

  def show
    @user = User.new(email_address: @invite.email)
  end

  def create
    if authenticated?
      @invite.accept!(Current.user)
      redirect_to root_path, notice: "Invite accepted."
    else
      @user = User.new(params.expect(user: %i[name email_address password password_confirmation]))
      ApplicationRecord.transaction do
        @user.save!
        @invite.accept!(@user)
      end
      begin_two_factor(@user)
    end
  rescue ActiveRecord::RecordInvalid
    render :show, status: :unprocessable_entity
  rescue Invite::AlreadyUsed
    render :invalid, status: :not_found
  end

  private

  def set_invite
    @invite = Invite.find_usable(params[:token])
    render :invalid, status: :not_found unless @invite
  end
end
```

`app/controllers/memberships_controller.rb`:

```ruby
class MembershipsController < ApplicationController
  include BusinessScoped

  LAST_OWNER = "A business needs at least one owner."

  before_action :require_owner!
  before_action :set_member, only: %i[update destroy]

  def index
    @memberships = @business.memberships.includes(:user).order(:role)
  end

  def update
    role = params.expect(membership: [:role])[:role]
    return redirect_to(business_memberships_path(@business), alert: LAST_OWNER) if @member.last_owner? && role != "owner"

    @member.update!(role: role)
    redirect_to business_memberships_path(@business), notice: "Role updated."
  end

  def destroy
    return redirect_to(business_memberships_path(@business), alert: LAST_OWNER, status: :see_other) if @member.last_owner?

    @member.destroy!
    redirect_to business_memberships_path(@business), notice: "Member removed.", status: :see_other
  end

  private

  def set_member
    @member = @business.memberships.find(params[:id])
  end
end
```

`app/controllers/people_controller.rb`:

```ruby
class PeopleController < ApplicationController
  before_action :require_household_owner!
  before_action :set_person, only: %i[edit update]

  def index
    @people = Household.instance.people.includes(:user).order(:name)
  end

  def new
    @person = Household.instance.people.new
  end

  def create
    @person = Household.instance.people.new(person_params)
    if @person.save
      redirect_to people_path, notice: "Person added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @person.update(person_params)
      redirect_to people_path, notice: "Person updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_person
    @person = Household.instance.people.find(params[:id])
  end

  def person_params
    params.expect(person: %i[name user_id])
  end
end
```

- [ ] **Step 7: Views**

`app/views/invites/new.html.erb`:

```erb
<h1>Invite someone</h1>
<%= form_with model: @invite do |f| %>
  <%= render "shared/errors", record: @invite %>
  <p><%= f.label :email, "Email (optional)" %> <%= f.email_field :email %></p>
  <table>
    <thead><tr><th>Business</th><th>Access</th></tr></thead>
    <tbody>
      <% @grantable.each do |business| %>
        <tr>
          <td><label for="invite_grant_roles_<%= business.id %>"><%= business.name %></label></td>
          <td><%= select_tag "invite[grant_roles][#{business.id}]",
                options_for_select([["No access", ""], ["Viewer", "viewer"], ["Editor", "editor"], ["Owner", "owner"]]),
                id: "invite_grant_roles_#{business.id}" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= f.submit "Create invite" %>
<% end %>
```

`app/views/invites/show.html.erb`:

```erb
<h1>Invite created</h1>
<p>Send this link to <%= @invite.email.presence || "the person you're inviting" %>. It works once and expires <%= l(@invite.expires_at, format: :long) %>. It won't be shown again.</p>
<p><code id="join-url"><%= @join_url %></code></p>
<%= link_to "Back to invites", invites_path %>
```

`app/views/invites/index.html.erb`:

```erb
<h1>Invites</h1>
<table>
  <thead><tr><th>Email</th><th>Access</th><th>Status</th></tr></thead>
  <tbody>
    <% @invites.each do |invite| %>
      <tr>
        <td><%= invite.email %></td>
        <td><%= invite.grants.map { "#{_1.business.name}: #{_1.role}" }.join(", ") %></td>
        <td>
          <% if invite.accepted_at %>Accepted by <%= invite.accepted_by.name %>
          <% elsif invite.expires_at.past? %>Expired
          <% else %>Pending until <%= l(invite.expires_at, format: :short) %><% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
<%= link_to "New invite", new_invite_path %>
```

`app/views/invite_acceptances/show.html.erb`:

```erb
<h1>Join goodbooks</h1>
<p>You've been invited to: <%= @invite.grants.map { "#{_1.business.name} (#{_1.role})" }.join(", ") %>.</p>
<% if authenticated? %>
  <%= button_to "Accept invite", join_path(params[:token]) %>
<% else %>
  <%= form_with model: @user, url: join_path(params[:token]) do |f| %>
    <%= render "shared/errors", record: @user %>
    <p><%= f.label :name %> <%= f.text_field :name, required: true %></p>
    <p><%= f.label :email_address %> <%= f.email_field :email_address, required: true %></p>
    <p><%= f.label :password %> <%= f.password_field :password, required: true, minlength: 12 %></p>
    <p><%= f.label :password_confirmation %> <%= f.password_field :password_confirmation, required: true %></p>
    <%= f.submit "Join" %>
  <% end %>
  <p>Already have an account? <%= link_to "Sign in", new_session_path %>, then open this link again.</p>
<% end %>
```

`app/views/invite_acceptances/invalid.html.erb`:

```erb
<h1>Invite not valid</h1>
<p>This invite link has expired or was already used. Ask for a new one.</p>
```

`app/views/memberships/index.html.erb`:

```erb
<%= business_nav @business %>
<h1>Members</h1>
<table>
  <thead><tr><th>Name</th><th>Email</th><th>Role</th><th></th></tr></thead>
  <tbody>
    <% @memberships.each do |membership| %>
      <tr>
        <td><%= membership.user.name %></td>
        <td><%= membership.user.email_address %></td>
        <td>
          <%= form_with model: [@business, membership], class: "inline-form" do |f| %>
            <%= f.select :role, Membership::RANK.keys.map { [_1.humanize, _1] } %>
            <%= f.submit "Save" %>
          <% end %>
        </td>
        <td><%= button_to "Remove", business_membership_path(@business, membership), method: :delete %></td>
      </tr>
    <% end %>
  </tbody>
</table>
<%= link_to "Invite someone", new_invite_path %>
```

`app/views/people/index.html.erb`:

```erb
<h1>People (taxpayers)</h1>
<table>
  <thead><tr><th>Name</th><th>Login</th><th></th></tr></thead>
  <tbody>
    <% @people.each do |person| %>
      <tr><td><%= person.name %></td><td><%= person.user&.email_address || "—" %></td><td><%= link_to "Edit", edit_person_path(person) %></td></tr>
    <% end %>
  </tbody>
</table>
<%= link_to "Add person", new_person_path if @people.size < Person::MAX_PER_HOUSEHOLD %>
```

`app/views/people/_form.html.erb`:

```erb
<%= form_with model: person do |f| %>
  <%= render "shared/errors", record: person %>
  <p><%= f.label :name %> <%= f.text_field :name, required: true %></p>
  <p>
    <%= f.label :user_id, "Login" %>
    <%= f.collection_select :user_id, User.where.missing(:person).or(User.where(id: person.user_id)).order(:name), :id, :email_address, include_blank: "None" %>
  </p>
  <%= f.submit %>
<% end %>
```

`app/views/people/new.html.erb`:

```erb
<h1>Add person</h1>
<%= render "form", person: @person %>
```

`app/views/people/edit.html.erb`:

```erb
<h1>Edit <%= @person.name %></h1>
<%= render "form", person: @person %>
```

Append to the business nav `<ul>`:

```erb
    <% if current_membership&.owner? %>
      <li><%= link_to "Members", business_memberships_path(business) %></li>
    <% end %>
```

In the layout `site-nav`, before "Sign out":

```erb
          <%= link_to "Invites", invites_path if Current.user.household_owner? || Current.user.memberships.owner.exists? %>
          <%= link_to "People", people_path if Current.user.household_owner? %>
```

- [ ] **Step 8: Run the specs**

Run: `bundle exec rspec`
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add invite links, member management, and household people"
```

---

### Task 19: Nightly SQLite backups

**Files:**
- Create: `app/jobs/database_backup_job.rb`
- Modify: `config/recurring.yml`
- Test: `spec/jobs/database_backup_job_spec.rb`

**Interfaces:**
- Produces: `DatabaseBackupJob.perform_now(dir: String = "storage/backups", today: Date = Date.current)` writes `goodbooks-YYYY-MM-DD.sqlite3` using SQLite's online backup API and keeps the newest `DatabaseBackupJob::KEEP = 14`

- [ ] **Step 1: Write the failing spec**

`spec/jobs/database_backup_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe DatabaseBackupJob do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  it "writes a readable copy of the database" do
    DatabaseBackupJob.perform_now(dir: dir, today: Date.new(2026, 10, 5))
    path = File.join(dir, "goodbooks-2026-10-05.sqlite3")
    tables = SQLite3::Database.new(path).execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
    expect(tables).to include("households", "transactions")
  end

  it "keeps the newest 14 backups" do
    16.times { |i| FileUtils.touch(File.join(dir, "goodbooks-2026-09-#{format("%02d", i + 1)}.sqlite3")) }
    DatabaseBackupJob.perform_now(dir: dir, today: Date.new(2026, 10, 5))
    files = Dir.children(dir).sort
    expect(files.size).to eq(14)
    expect(files.last).to eq("goodbooks-2026-10-05.sqlite3")
    expect(files.first).to eq("goodbooks-2026-09-04.sqlite3")
  end
end
```

Run: `bundle exec rspec spec/jobs/database_backup_job_spec.rb`
Expected: FAIL (`uninitialized constant DatabaseBackupJob`).

- [ ] **Step 2: Implement**

`app/jobs/database_backup_job.rb`:

```ruby
class DatabaseBackupJob < ApplicationJob
  KEEP = 14

  def perform(dir: Rails.root.join("storage/backups").to_s, today: Date.current)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "goodbooks-#{today.iso8601}.sqlite3")
    FileUtils.rm_f(path)

    destination = SQLite3::Database.new(path)
    backup = SQLite3::Backup.new(destination, "main", ActiveRecord::Base.connection.raw_connection, "main")
    backup.step(-1)
    backup.finish
    destination.close

    Dir.glob(File.join(dir, "goodbooks-*.sqlite3")).sort.reverse.drop(KEEP).each { File.delete(_1) }
  end
end
```

Add to `config/recurring.yml` under the `production:` key (keep existing entries):

```yaml
  database_backup:
    class: DatabaseBackupJob
    schedule: every day at 3am
```

Run: `bundle exec rspec spec/jobs/database_backup_job_spec.rb`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Add nightly SQLite backup job"
```

---

### Task 20: Reference seeds and demo data

**Files:**
- Modify: `db/seeds.rb`
- Create: `lib/demo_seeder.rb`, `lib/tasks/demo.rake`
- Test: `spec/lib/demo_seeder_spec.rb`, `spec/db/seeds_spec.rb`

**Interfaces:**
- Consumes: `BusinessProvisioner`, `CsvImport::Mapping`, all models
- Produces:
  - `db/seeds.rb`: idempotently creates `TaxParameters` for 2026 (mileage rate 72.5¢ → `725`)
  - `DemoSeeder.new(out: IO, today: Date, random: Random).run`, `DemoSeeder::PASSWORD`, `DemoSeeder::OTP_SECRET`
  - `bin/rails demo:seed`, `bin/rails demo:reset`

- [ ] **Step 1: Verify the 2026 rate**

Look up the IRS notice announcing the 2026 business standard mileage rate (search: "IRS standard mileage rate 2026"). The plan assumes 72.5¢. If the published number differs, use it below and in the spec.

- [ ] **Step 2: Write failing specs**

`spec/db/seeds_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "db/seeds.rb" do
  it "creates reference data idempotently" do
    2.times { load Rails.root.join("db/seeds.rb") }
    expect(TaxParameters.for_year(2026).standard_mileage_rate_tenth_cents).to eq(725)
    expect(TaxParameters.count).to eq(1)
  end
end
```

`spec/lib/demo_seeder_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe DemoSeeder do
  let(:out) { StringIO.new }
  let(:today) { Date.new(2026, 10, 5) }

  def run = DemoSeeder.new(out: out, today: today).run

  it "builds a household with two businesses, three users, and a year of activity" do
    run
    expect(Household.count).to eq(1)
    expect(Business.pluck(:name)).to contain_exactly("Pat Consulting", "Jordan Design Studio")
    pat, jordan, accountant = %w[pat jordan accountant].map { User.find_by!(email_address: "#{_1}@example.com") }
    expect(pat).to be_household_owner
    expect(jordan.membership_for(Business.find_by!(name: "Jordan Design Studio"))).to be_editor
    expect(jordan.membership_for(Business.find_by!(name: "Pat Consulting"))).to be_viewer
    expect(accountant.can_view_household?).to be(true)
    expect(Transaction.inbox.count).to be > 0
    expect(Transaction.where.not(category_id: nil).count).to be > 50
    expect(Transaction.where(transfer: true).count).to be > 0
    expect(MileageEntry.count).to be > 10
    expect(Rule.count).to eq(4)
    expect(Transaction.maximum(:posted_on)).to be <= today
  end

  it "uses a known TOTP secret and prints the logins" do
    run
    expect(User.find_by!(email_address: "pat@example.com").otp_secret).to eq(DemoSeeder::OTP_SECRET)
    expect(out.string).to include("pat@example.com", DemoSeeder::PASSWORD, DemoSeeder::OTP_SECRET)
  end

  it "refuses to run twice" do
    run
    expect { run }.to raise_error(RuntimeError, /already exists/)
  end

  it "refuses to run in production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
    expect { run }.to raise_error(RuntimeError, /production/)
    expect(Household.count).to eq(0)
  end
end
```

Run: `bundle exec rspec spec/db/seeds_spec.rb spec/lib/demo_seeder_spec.rb`
Expected: FAIL (seeds create nothing; `uninitialized constant DemoSeeder`).

- [ ] **Step 3: Implement seeds**

`db/seeds.rb`:

```ruby
# Reference data for every environment. Safe to run repeatedly.
# Schedule C categories come from CategoryTemplate (code), applied when a business is created.

TaxParameters.find_or_create_by!(year: 2026) do |params|
  params.standard_mileage_rate_tenth_cents = 725 # IRS 2026 business rate: 72.5¢/mile
end
```

- [ ] **Step 4: Implement the demo seeder**

`lib/demo_seeder.rb`:

```ruby
class DemoSeeder
  PASSWORD = "demo password 123"
  OTP_SECRET = "GOODBOOKSDEMOSECRETKEYABCDEFGHIJ"
  USERS = [
    ["pat@example.com", "Pat Example"],
    ["jordan@example.com", "Jordan Example"],
    ["accountant@example.com", "Avery Accountant"]
  ].freeze

  def initialize(out: $stdout, today: Date.current, random: Random.new(42))
    @out = out
    @today = today
    @random = random
  end

  def run
    raise "demo:seed refuses to run in production" if Rails.env.production?
    raise "A household already exists. Run bin/rails demo:reset to start over." if Household.exists?

    ApplicationRecord.transaction { build }
    print_summary
  end

  private

  def build
    household = Household.create!(name: "Example Household")
    pat, jordan, accountant = USERS.map.with_index do |(email, name), i|
      User.create!(email_address: email, name: name, password: PASSWORD, household_owner: i.zero?,
                   otp_secret: OTP_SECRET, otp_enabled_at: Time.current)
    end
    pat_person = household.people.create!(name: pat.name, user: pat)
    jordan_person = household.people.create!(name: jordan.name, user: jordan)

    consulting = BusinessProvisioner.call(household.businesses.new(name: "Pat Consulting", person: pat_person), owner: pat)
    studio = BusinessProvisioner.call(household.businesses.new(name: "Jordan Design Studio", person: jordan_person), owner: pat)
    Membership.create!(user: jordan, business: studio, role: "editor")
    Membership.create!(user: jordan, business: consulting, role: "viewer")
    [consulting, studio].each { Membership.create!(user: accountant, business: _1, role: "viewer") }

    seed_business(consulting, client: "ACME CORP", income_cents: 850_000, software: ["ADOBE CREATIVE CLOUD", 5_499])
    seed_business(studio, client: "BLUE OX DESIGN CO", income_cents: 520_000, software: ["FIGMA", 1_500])
  end

  def seed_business(business, client:, income_cents:, software:)
    bank = business.accounts.create!(
      name: "Business Checking", source: "csv", kind: "checking",
      csv_mapping: CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount").to_h
    )
    cash = business.accounts.find_by!(name: "Cash")
    categories = business.categories.index_by(&:name)
    business.rules.create!(field: "payee", operator: "contains", value: software.first.split.first, outcome: "categorize",
                           category: categories.fetch("Software"))
    business.rules.create!(field: "payee", operator: "contains", value: "CARD PAYMENT", outcome: "transfer")

    sequence = 0
    12.downto(0) do |months_ago|
      month = (@today << months_ago).beginning_of_month
      inbox = months_ago.zero?
      add = lambda do |day, payee, cents, category|
        date = month + (day - 1)
        next if date > @today

        sequence += 1
        attrs = { posted_on: date, payee: payee, amount_cents: cents, external_id: "demo-#{business.id}-#{sequence}" }
        unless inbox
          if category == :transfer
            attrs.merge!(transfer: true, categorized_by: "rule")
          else
            attrs.merge!(category: categories.fetch(category), categorized_by: "user")
          end
        end
        bank.transactions.create!(attrs)
      end

      add.(3, "#{client} PAYMENT", income_cents, "Sales")
      add.(5, software.first, -software.last, "Software")
      add.(8, "VERIZON WIRELESS", -8_500, "Phone and internet")
      add.(12, "OFFICE DEPOT", -(2_000 + @random.rand(8_000)), "Office expense")
      add.(18, "LOCAL CAFE", -(1_500 + @random.rand(4_000)), "Meals")
      add.(25, "CARD PAYMENT THANK YOU", -50_000, :transfer)

      if month + 14 <= @today
        cash.transactions.create!(posted_on: month + 14, payee: "Hardware store", amount_cents: -(1_000 + @random.rand(3_000)),
                                  category: categories.fetch("Supplies"), categorized_by: "user")
      end
      if month + 9 <= @today
        business.mileage_entries.create!(driven_on: month + 9, purpose: "Client meeting", from_location: "Home office",
                                         to_location: "#{client.titleize} office", miles: "18.4", round_trip: true)
      end
    end
  end

  def print_summary
    @out.puts "Demo data loaded."
    @out.puts "Password for every user: #{PASSWORD}"
    @out.puts "TOTP secret for every user (add to your authenticator app): #{OTP_SECRET}"
    USERS.each { |email, name| @out.puts "  #{name}: #{email}" }
    @out.puts "Warning: no TaxParameters for #{@today.year}; run bin/rails db:seed." unless TaxParameters.for_year(@today.year)
  end
end
```

`lib/tasks/demo.rake`:

```ruby
namespace :demo do
  desc "Load demo household data (refuses to run in production)"
  task seed: :environment do
    DemoSeeder.new.run
  end

  desc "Reset the database, load reference seeds, then demo data"
  task reset: %w[db:reset demo:seed]
end
```

`lib/` is autoloaded by Rails 8's default `config.autoload_lib(ignore: %w[assets tasks])`. Confirm that line exists in `config/application.rb`.

- [ ] **Step 5: Run the specs, then try it**

Run: `bundle exec rspec`
Expected: all PASS, no seeder output (it writes to the `StringIO`).

Run: `bin/rails demo:reset`
Expected: prints the logins. Start `bin/dev`, log in as `pat@example.com` with the password and a code from an authenticator loaded with the printed secret, and click through Inbox, Transactions, Mileage, P&L, Schedule C, and Household.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add reference seeds and demo data tasks"
```

---

### Task 21: Production config, Docker Compose, README

**Files:**
- Modify: `config/environments/production.rb`, `config/credentials.yml.enc` (encryption keys)
- Create: `docker-compose.yml`, `.env.example`, `README.md` (replace the generated one)
- Test: `spec/config/production_config_spec.rb`

**Interfaces:**
- Produces: `docker compose up -d` serves the app on port 3000 with the `goodbooks_storage` volume. Required env: `RAILS_MASTER_KEY`, `APP_HOST`.

- [ ] **Step 1: Write the failing spec for host checks**

`spec/config/production_config_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Production host configuration" do
  it "allows APP_HOST and keeps /up reachable for health checks" do
    config = File.read(Rails.root.join("config/environments/production.rb"))
    expect(config).to include('config.hosts = [ENV.fetch("APP_HOST", "localhost")]')
    expect(config).to include("config.host_authorization = { exclude: ->(request) { request.path == \"/up\" } }")
    expect(config).to include("config.assume_ssl = true")
    expect(config).to include("config.force_ssl = true")
  end
end
```

(This is a config check. Production can't boot inside the test suite, so the real verification is Step 5.)

Run: `bundle exec rspec spec/config/production_config_spec.rb`
Expected: FAIL.

- [ ] **Step 2: Production config**

In `config/environments/production.rb`, make sure these lines exist (uncomment or edit the generated ones):

```ruby
  config.assume_ssl = true
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
  config.hosts = [ENV.fetch("APP_HOST", "localhost")]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
```

Run: `bundle exec rspec spec/config/production_config_spec.rb`
Expected: PASS. (The `"localhost"` default keeps `assets:precompile` working during `docker build`, where `APP_HOST` isn't set; compose requires it at runtime.)

- [ ] **Step 3: Add encryption keys to credentials**

```bash
bin/rails runner '
  creds = Rails.application.credentials
  data = YAML.safe_load(creds.read.presence || "{}") || {}
  data["active_record_encryption"] ||= {
    "primary_key" => SecureRandom.alphanumeric(32),
    "deterministic_key" => SecureRandom.alphanumeric(32),
    "key_derivation_salt" => SecureRandom.alphanumeric(32)
  }
  creds.write(data.to_yaml)
'
bin/rails runner 'puts Rails.application.credentials.active_record_encryption.keys.sort.inspect'
```

Expected output: `[:deterministic_key, :key_derivation_salt, :primary_key]`. `config/master.key` stays git-ignored; it is the `RAILS_MASTER_KEY`.

- [ ] **Step 4: Compose file and env example**

`docker-compose.yml`:

```yaml
services:
  app:
    build: .
    image: goodbooks:latest
    restart: unless-stopped
    ports:
      - "3000:80"
    environment:
      RAILS_MASTER_KEY: ${RAILS_MASTER_KEY:?set RAILS_MASTER_KEY in .env}
      APP_HOST: ${APP_HOST:?set APP_HOST in .env}
      SOLID_QUEUE_IN_PUMA: "true"
    volumes:
      - goodbooks_storage:/rails/storage

volumes:
  goodbooks_storage:
```

`.env.example`:

```
# Copy to .env and fill in. Never commit .env.
RAILS_MASTER_KEY=contents-of-config/master.key
APP_HOST=books.example.com
```

Add `.env` to `.gitignore` if it isn't there.

- [ ] **Step 5: Build and smoke-test the container**

```bash
cp .env.example .env
sed -i '' "s|contents-of-config/master.key|$(cat config/master.key)|; s|books.example.com|localhost|" .env
docker compose build
docker compose up -d
sleep 10
curl -fsS http://localhost:3000/up && echo OK
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: localhost" http://localhost:3000/
docker compose down
rm .env
```

Expected: `OK`, then `302` (redirect to `/setup`). If the build fails on the Ruby version, confirm `.ruby-version` is `4.0.7` and the Dockerfile's `ARG RUBY_VERSION` matches.

- [ ] **Step 6: README**

Replace `README.md`:

````markdown
# goodbooks

Self-hosted bookkeeping for a freelancing household: income and expenses per business, CSV imports, a rules-driven categorization inbox, mileage, P&L and Schedule C reports, and role-based sharing with your accountant. Design: `docs/superpowers/specs/2026-10-05-goodbooks-design.md`.

## Development

```bash
bin/setup               # install gems, prepare the database
bin/rails demo:reset    # load demo data; prints logins and the TOTP secret
bin/dev                 # http://localhost:3000
bundle exec rspec       # test suite
```

## Deploying on a home server

1. Copy `.env.example` to `.env`. Set `RAILS_MASTER_KEY` (from `config/master.key`) and `APP_HOST` (the public hostname).
2. `docker compose up -d --build`
3. Expose port 3000 through a tunnel. TLS terminates at the tunnel.
   - **Cloudflare Tunnel:** `cloudflared tunnel create goodbooks`, route `APP_HOST` to `http://localhost:3000`, run `cloudflared tunnel run goodbooks` (or install it as a service).
   - **Tailscale Funnel:** `tailscale funnel --bg 3000`; set `APP_HOST` to your `*.ts.net` name.
4. Visit `https://APP_HOST`, create the household, and enroll in 2FA.

Data lives in the `goodbooks_storage` Docker volume (SQLite databases, uploads, backups).

## Backups

A nightly job (03:00) writes `storage/backups/goodbooks-YYYY-MM-DD.sqlite3` and keeps 14 copies. Copy them offsite:

```bash
docker run --rm -v goodbooks_storage:/data -v "$PWD":/out alpine \
  sh -c 'cp /data/backups/*.sqlite3 /out/'
```

## Each tax year

Household owner → Tax parameters → add the year's IRS standard mileage rate once the IRS publishes it.
````

- [ ] **Step 7: Run everything**

Run: `bundle exec rspec`
Expected: all PASS, clean output.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add production config, Docker Compose, and README"
```
