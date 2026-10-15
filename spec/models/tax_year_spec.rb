require "rails_helper"

RSpec.describe TaxYear do
  let(:household) { create(:household) }

  it "finds or creates the year's row" do
    first = described_class.for(household, 2026)
    expect(described_class.for(household, 2026)).to eq(first)
    expect(described_class.count).to eq(1)
  end

  it "gives a prior year only when both figures are present" do
    expect(build(:tax_year, household:, prior_year_total_tax_cents: 100).prior_year).to be_nil
    expect(build(:tax_year, household:, prior_year_total_tax_cents: 100, prior_year_agi_cents: -500).prior_year)
      .to eq(Tax::PriorYear.new(total_tax_cents: 100, agi_cents: -500))
  end

  it "takes money text, allows a negative AGI, and rejects negative tax" do
    year = build(:tax_year, household:, prior_year_total_tax: "24,000", prior_year_agi: "-1,500.50")
    expect(year).to be_valid
    expect(year.prior_year_agi_cents).to eq(-150_050)
    expect(build(:tax_year, household:, prior_year_total_tax: "-1")).not_to be_valid
  end

  it "rejects a year outside 2000–2100" do
    expect(build(:tax_year, household:, year: 1999)).not_to be_valid
  end
end
