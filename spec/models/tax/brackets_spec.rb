require "rails_helper"

RSpec.describe Tax::Brackets do
  let(:brackets) { [ Tax::Bracket.new(floor_cents: 0, rate_bps: 1000), Tax::Bracket.new(floor_cents: 2_480_000, rate_bps: 1200), Tax::Bracket.new(floor_cents: 10_080_000, rate_bps: 2200) ] }

  it "taxes nothing at zero" do
    expect(described_class.slices(0, brackets)).to eq([])
    expect(described_class.tax_cents(0, brackets)).to eq(0)
  end

  it "slices progressively and rounds each slice once" do
    # $48,588.18: 10% × 24,800.00 = 2,480.00; 12% × 23,788.18 = 2,854.5816 → 2,854.58
    slices = described_class.slices(4_858_818, brackets)
    expect(slices.map(&:tax_cents)).to eq([ 248_000, 285_458 ])
    expect(slices.last).to have_attributes(rate_bps: 1200, from_cents: 2_480_000, to_cents: 4_858_818, taxed_cents: 2_378_818)
    expect(described_class.tax_cents(4_858_818, brackets)).to eq(533_458)
  end

  it "uses the top bracket without an upper bound" do
    # $200,000: 2,480.00 + 12% × 76,000.00 = 9,120.00 + 22% × 99,200.00 = 21,824.00
    expect(described_class.tax_cents(20_000_000, brackets)).to eq(248_000 + 912_000 + 2_182_400)
  end

  it "stops exactly at a floor" do
    expect(described_class.slices(2_480_000, brackets).size).to eq(1)
  end
end
