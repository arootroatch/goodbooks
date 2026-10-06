class DemoSeeder
  PASSWORD = "demo password 123"
  OTP_SECRET = "GOODBOOKSDEMOSECRETKEYABCDEFGHIJ"
  USERS = [
    [ "pat@example.com", "Pat Example" ],
    [ "jordan@example.com", "Jordan Example" ],
    [ "accountant@example.com", "Avery Accountant" ]
  ].freeze

  def initialize(out: $stdout, today: Date.current, random: Random.new(42))
    @out = out
    @today = today
    @random = random
  end

  def run
    raise "demo:seed refuses to run in production" if Rails.env.production?
    raise "A household already exists. Run bin/rails demo:reset to start over." if Household.exists?

    ApplicationRecord.transaction do
      build
      ensure_tax_parameters
      ensure_inbox_non_empty
    end
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
    [ consulting, studio ].each { Membership.create!(user: accountant, business: _1, role: "viewer") }

    seed_business(consulting, client: "ACME CORP", income_cents: 850_000, software: [ "ADOBE CREATIVE CLOUD", 5_499 ])
    seed_business(studio, client: "BLUE OX DESIGN CO", income_cents: 520_000, software: [ "FIGMA", 1_500 ])
    seed_invoices(consulting, payer: "ACME CORP", others: [ "Northwind Traders", "Globex" ], prefix: "INV-")
    seed_invoices(studio, payer: "BLUE OX DESIGN CO", others: [ "Initech", "Umbrella Bakery" ], prefix: "JDS-")
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

  def ensure_tax_parameters
    years_with_activity = years_covered_by_transactions_and_mileage
    default_mileage_rate = 725

    years_with_activity.each do |year|
      next if TaxParameters.exists?(year: year)

      latest_params = TaxParameters.order(:year).last
      if latest_params
        mileage_rate = latest_params.standard_mileage_rate_tenth_cents
        TaxParameters.create!(year: year, standard_mileage_rate_tenth_cents: mileage_rate)
        @out.puts "Demo: copied #{mileage_rate} mileage rate to #{year}"
      else
        TaxParameters.create!(year: year, standard_mileage_rate_tenth_cents: default_mileage_rate)
        @out.puts "Demo: no tax parameters found; seeded #{year} with default 72.5¢ mileage rate"
      end
    end
  end

  def years_covered_by_transactions_and_mileage
    transaction_years = Transaction.pluck(:posted_on).map(&:year).uniq
    mileage_years = MileageEntry.pluck(:driven_on).map(&:year).uniq
    (transaction_years + mileage_years + [ @today.year ]).uniq.sort
  end

  def ensure_inbox_non_empty
    return if Transaction.inbox.count > 0

    Transaction.order(posted_on: :desc, id: :desc).limit(3)
      .update_all(category_id: nil, transfer: false, categorized_by: nil, rule_id: nil)
  end

  def print_summary
    @out.puts "Demo data loaded."
    @out.puts "Password for every user: #{PASSWORD}"
    @out.puts "TOTP secret for every user (add to your authenticator app): #{OTP_SECRET}"
    USERS.each { |email, name| @out.puts "  #{name}: #{email}" }
    @out.puts "Warning: no TaxParameters for #{@today.year}; run bin/rails db:seed." unless TaxParameters.for_year(@today.year)
  end
end
