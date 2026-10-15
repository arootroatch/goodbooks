require "rails_helper"

RSpec.describe Tax::HomeOfficeDeduction do
  let(:office_class) do
    Struct.new(:calculation, :office_sqft, :home_sqft, :rent_cents, :mortgage_interest_cents, :utilities_cents,
               :insurance_cents, :repairs_cents, :other_cents, :depreciation_cents, keyword_init: true)
  end

  def office(**attrs)
    office_class.new(calculation: "simplified", office_sqft: 200, home_sqft: nil, rent_cents: 0, mortgage_interest_cents: 0, utilities_cents: 0,
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
