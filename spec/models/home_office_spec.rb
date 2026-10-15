require "rails_helper"

RSpec.describe HomeOffice do
  let(:business) { create(:business) }

  it "defaults blank costs to zero" do
    office = described_class.create!(business:, year: 2026, calculation: "simplified", office_sqft: 200, rent: "")
    expect(office.rent_cents).to eq(0)
  end

  it "requires a home size at least the office size for the regular method" do
    expect(build(:home_office, business:, calculation: "regular", home_sqft: nil)).not_to be_valid
    office = build(:home_office, business:, calculation: "regular", office_sqft: 300, home_sqft: 200)
    expect(office).not_to be_valid
    expect(office.errors[:home_sqft]).to eq([ "must be at least the office's square feet" ])
  end

  it "rejects the personal book" do
    office = build(:home_office, business: create(:business, :personal))
    expect(office).not_to be_valid
    expect(office.errors[:business]).to eq([ "must be a business, not the personal book" ])
  end

  it "rejects negative costs" do
    expect(build(:home_office, business:, utilities: "-5")).not_to be_valid
  end

  it "computes its deduction from the year's parameters" do
    params = build(:tax_parameters, :federal_2026)
    expect(build(:home_office, business:, office_sqft: 200).deduction_cents(params)).to eq(100_000)
    regular = build(:home_office, business:, calculation: "regular", office_sqft: 200, home_sqft: 2_000, rent: "24,000")
    expect(regular.deduction_cents(nil)).to eq(240_000)
  end

  it "has no simplified deduction without a rate" do
    expect(build(:home_office, business:).deduction_cents(nil)).to be_nil
  end
end
