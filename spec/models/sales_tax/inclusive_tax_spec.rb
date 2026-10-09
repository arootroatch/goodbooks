require "rails_helper"

RSpec.describe SalesTax::InclusiveTax do
  it "backs the tax out of a tax-inclusive gross" do
    expect(described_class.call(gross_cents: 100_000, rate_bps: 925)).to eq(8_467)
    expect(described_class.call(gross_cents: 10_925, rate_bps: 925)).to eq(925)
  end

  it "rounds half up once" do
    expect(described_class.call(gross_cents: 3, rate_bps: 10_000)).to eq(2)
  end

  it "is zero for an empty or negative base" do
    expect(described_class.call(gross_cents: 0, rate_bps: 925)).to eq(0)
    expect(described_class.call(gross_cents: -500, rate_bps: 925)).to eq(0)
  end
end
