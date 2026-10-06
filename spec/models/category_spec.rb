require "rails_helper"

RSpec.describe Category do
  it "requires an income line for income categories" do
    expect(build(:category, kind: "income", schedule_c_line: "18")).not_to be_valid
    expect(build(:category, kind: "income", schedule_c_line: "1")).to be_valid
  end

  it "requires an expense line for expense categories" do
    expect(build(:category, kind: "expense", schedule_c_line: "1")).not_to be_valid
  end

  it "does not allow line 30 (home office comes from sub-project 5)" do
    expect(build(:category, schedule_c_line: "30")).not_to be_valid
  end

  it "keeps deductible_bps between 0 and 10000" do
    expect(build(:category, deductible_bps: 10_001)).not_to be_valid
    expect(build(:category, deductible_bps: -1)).not_to be_valid
  end

  describe "#deductible_percent" do
    it "reads bps as a percent string" do
      expect(build(:category, deductible_bps: 5000).deductible_percent).to eq("50")
      expect(build(:category, deductible_bps: 3333).deductible_percent).to eq("33.33")
    end

    it "writes a percent string as bps" do
      category = build(:category, deductible_percent: "33.33")
      expect(category.deductible_bps).to eq(3333)
    end

    it "accepts valid numeric forms" do
      expect(build(:category, deductible_percent: "50").deductible_bps).to eq(5000)
      expect(build(:category, deductible_percent: "33.33").deductible_bps).to eq(3333)
      expect(build(:category, deductible_percent: "100").deductible_bps).to eq(10_000)
    end

    it "rejects rational form" do
      category = build(:category, deductible_percent: "1/2")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end

    it "rejects scientific notation" do
      category = build(:category, deductible_percent: "1e2")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end

    it "rejects underscore separators" do
      category = build(:category, deductible_percent: "1_0")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end

    it "rejects empty string" do
      category = build(:category, deductible_percent: "")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end

    it "flags garbage" do
      category = build(:category, deductible_percent: "half")
      expect(category).not_to be_valid
      expect(category.errors[:deductible_percent]).to include("is not a number")
    end
  end

  it "has a unique name per business" do
    existing = create(:category)
    expect(build(:category, business: existing.business, name: existing.name)).not_to be_valid
  end
end
