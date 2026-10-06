require "rails_helper"

RSpec.describe RuleEngine do
  let(:fake_rule_class) { Struct.new(:name, :field, :operator, :value, :amount_min_cents, :amount_max_cents, keyword_init: true) }

  def rule(name, field: "payee", operator: "contains", value:, min: nil, max: nil)
    fake_rule_class.new(name:, field:, operator:, value:, amount_min_cents: min, amount_max_cents: max)
  end

  let(:attrs) { { payee: "  ADOBE   Creative Cloud ", memo: "Monthly SUB", amount_cents: -5499 } }

  it "matches contains, case-insensitively, with normalized whitespace" do
    expect(RuleEngine.match(attrs, [ rule("a", value: "adobe creative") ])&.name).to eq("a")
  end

  it "matches equals against the whole normalized value" do
    expect(RuleEngine.match(attrs, [ rule("a", operator: "equals", value: "adobe creative cloud") ])&.name).to eq("a")
    expect(RuleEngine.match(attrs, [ rule("a", operator: "equals", value: "adobe") ])).to be_nil
  end

  it "matches starts_with" do
    expect(RuleEngine.match(attrs, [ rule("a", operator: "starts_with", value: "ADOBE") ])&.name).to eq("a")
    expect(RuleEngine.match(attrs, [ rule("a", operator: "starts_with", value: "cloud") ])).to be_nil
  end

  it "matches on memo" do
    expect(RuleEngine.match(attrs, [ rule("a", field: "memo", value: "monthly") ])&.name).to eq("a")
  end

  it "treats a nil memo as empty" do
    expect(RuleEngine.match(attrs.merge(memo: nil), [ rule("a", field: "memo", value: "x") ])).to be_nil
  end

  it "applies inclusive absolute amount bounds" do
    expect(RuleEngine.match(attrs, [ rule("a", value: "adobe", min: 5499, max: 5499) ])&.name).to eq("a")
    expect(RuleEngine.match(attrs, [ rule("a", value: "adobe", min: 5500) ])).to be_nil
    expect(RuleEngine.match(attrs, [ rule("a", value: "adobe", max: 5000) ])).to be_nil
  end

  it "returns the first match in order" do
    rules = [ rule("first", value: "creative"), rule("second", value: "adobe") ]
    expect(RuleEngine.match(attrs, rules).name).to eq("first")
  end

  it "returns nil when nothing matches" do
    expect(RuleEngine.match(attrs, [ rule("a", value: "google") ])).to be_nil
    expect(RuleEngine.match(attrs, [])).to be_nil
  end
end
