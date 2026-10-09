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

  it "knows which dates start a period in its calendar" do
    profile = build(:sales_tax_profile, starts_on: Date.new(2026, 2, 3), filing_frequency: "quarterly")
    expect(profile.period_start?(Date.new(2026, 1, 1))).to be(true)
    expect(profile.period_start?(Date.new(2026, 4, 1))).to be(true)
    expect(profile.period_start?(Date.new(2026, 2, 1))).to be(false)
    expect(profile.period_start?(Date.new(2025, 10, 1))).to be(false)
    expect(profile.period_start?(nil)).to be(false)
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

  it "locks the calendar once a remittance points at a period" do
    profile = create(:sales_tax_profile, business: business)
    create(:transaction, account: create(:account, business: business), category: business.categories.sales_tax_remittance.sole,
                         amount_cents: -100, posted_on: Date.new(2026, 4, 15), sales_tax_period_starts_on: Date.new(2026, 1, 1))
    expect(profile.reload.update(filing_frequency: "monthly")).to be(false)
  end
end
