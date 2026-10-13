require "rails_helper"

RSpec.describe PercentAttribute do
  it "parses percentages to basis points" do
    expect(described_class.parse_bps("9.25")).to eq(925)
    expect(described_class.parse_bps("9.25%")).to eq(925)
    expect(described_class.parse_bps(" 92.35 % ")).to eq(9235)
    expect(described_class.parse_bps("100")).to eq(10_000)
    expect(described_class.parse_bps("0")).to eq(0)
  end

  it "rejects anything else" do
    [ "", "abc", "9.255", "-1", "1000", "9,25" ].each do |input|
      expect { described_class.parse_bps(input) }.to raise_error(PercentAttribute::ParseError)
    end
  end

  it "formats basis points without trailing zeros" do
    expect(described_class.format_bps(925)).to eq("9.25")
    expect(described_class.format_bps(700)).to eq("7")
    expect(described_class.format_bps(1240)).to eq("12.4")
    expect(described_class.format_bps(9235)).to eq("92.35")
  end
end
