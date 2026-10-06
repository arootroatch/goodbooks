require "rails_helper"

RSpec.describe Rule do
  let(:business) { create(:business) }

  it "assigns increasing positions" do
    first = create(:rule, business: business)
    second = create(:rule, business: business)
    expect([first.position, second.position]).to eq([1, 2])
  end

  it "requires a category to categorize, from the same business" do
    expect(build(:rule, business: business, category: nil)).not_to be_valid
    expect(build(:rule, business: business, category: create(:category))).not_to be_valid
    expect(build(:rule, business: business, outcome: "transfer", category: nil)).to be_valid
  end

  it "rejects unknown fields, operators, and outcomes" do
    expect(build(:rule, field: "amount")).not_to be_valid
    expect(build(:rule, operator: "regex")).not_to be_valid
    expect(build(:rule, outcome: "delete")).not_to be_valid
  end

  it "requires a value that is not blank or whitespace" do
    expect(build(:rule, value: "")).not_to be_valid
    expect(build(:rule, value: "   ")).not_to be_valid
  end

  it "parses optional amount bounds and rejects negatives" do
    rule = build(:rule, business: business, amount_min: "", amount_max: "$100")
    expect(rule.amount_min_cents).to be_nil
    expect(rule.amount_max_cents).to eq(10000)
    expect(build(:rule, business: business, amount_min: "-5")).not_to be_valid
  end

  it "moves to a position and renumbers the rest" do
    a, b, c = Array.new(3) { create(:rule, business: business) }
    c.move_to!(1)
    expect(business.rules.ordered).to eq([c, a, b])
    expect(business.rules.ordered.pluck(:position)).to eq([1, 2, 3])
    c.move_to!(99)
    expect(business.rules.ordered).to eq([a, b, c])
    b.move_to!(0)
    expect(business.rules.ordered).to eq([b, a, c])
  end

  it "does not touch another business's rules" do
    other = create(:rule)
    mine = create(:rule, business: business)
    mine.move_to!(1)
    expect(other.reload.position).to eq(1)
  end
end
