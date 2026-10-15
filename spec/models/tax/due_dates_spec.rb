require "rails_helper"

RSpec.describe Tax::DueDates do
  it "uses the plain dates when they're business days (2026)" do
    expect(described_class.for(2026)).to eq([ Date.new(2026, 4, 15), Date.new(2026, 6, 15), Date.new(2026, 9, 15), Date.new(2027, 1, 15) ])
  end

  it "rolls past a weekend and Emancipation Day observed" do
    expect(described_class.for(2017).first).to eq(Date.new(2017, 4, 18)) # Sat 15 → Sun → Mon 17 observed (16th a Sunday) → Tue 18
    expect(described_class.for(2022).first).to eq(Date.new(2022, 4, 18)) # Fri 15 observed (16th a Saturday) → Sat → Sun → Mon 18
    expect(described_class.for(2023).first).to eq(Date.new(2023, 4, 18)) # Sat 15 → Sun → Mon 17 observed → Tue 18
  end

  it "rolls past MLK Day" do
    expect(described_class.for(2023).last).to eq(Date.new(2024, 1, 16)) # Mon Jan 15, 2024 is MLK Day
    expect(described_class.for(2027).last).to eq(Date.new(2028, 1, 18)) # Sat 15 → Sun → Mon 17 MLK → Tue 18
  end

  it "rolls a Sunday June 15 to Monday" do
    expect(described_class.for(2025)[1]).to eq(Date.new(2025, 6, 16))
  end

  describe ".quarter_on" do
    it "picks the first installment due on or after the date" do
      expect(described_class.quarter_on(2026, Date.new(2026, 1, 2))).to eq(1)
      expect(described_class.quarter_on(2026, Date.new(2026, 4, 15))).to eq(1)
      expect(described_class.quarter_on(2026, Date.new(2026, 4, 16))).to eq(2)
      expect(described_class.quarter_on(2026, Date.new(2026, 9, 16))).to eq(4)
      expect(described_class.quarter_on(2026, Date.new(2027, 1, 10))).to eq(4)
    end

    it "falls back to 4 after the last due date" do
      expect(described_class.quarter_on(2026, Date.new(2027, 3, 1))).to eq(4)
    end
  end
end
