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

  it "copies mileage rate from latest existing TaxParameters year" do
    TaxParameters.create!(year: 2026, standard_mileage_rate_tenth_cents: 700)
    today_early_month = Date.new(2026, 1, 1)
    DemoSeeder.new(out: out, today: today_early_month).run
    expect(TaxParameters.for_year(2025).standard_mileage_rate_tenth_cents).to eq(700)
    expect(TaxParameters.for_year(2026).standard_mileage_rate_tenth_cents).to eq(700)
    expect(out.string).to include("Demo: copied")
  end

  it "uses default mileage rate when no TaxParameters exist" do
    today_early_month = Date.new(2026, 1, 1)
    DemoSeeder.new(out: out, today: today_early_month).run
    expect(TaxParameters.for_year(2025).standard_mileage_rate_tenth_cents).to eq(725)
    expect(TaxParameters.for_year(2026).standard_mileage_rate_tenth_cents).to eq(725)
    expect(out.string).to include("Demo: no tax parameters found; seeded 2025 with default 72.5¢ mileage rate")
  end

  it "ensures inbox is non-empty on days 1-2 when seeding on those dates" do
    today_early_month = Date.new(2026, 1, 1)
    DemoSeeder.new(out: out, today: today_early_month).run
    expect(Transaction.inbox.count).to be > 0
  end

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
end
