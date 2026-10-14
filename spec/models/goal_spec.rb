require "rails_helper"

RSpec.describe Goal do
  let(:book) { create(:business) }

  it "requires a name, a known kind and a positive target" do
    expect(build(:goal, business: book, name: "")).not_to be_valid
    expect(build(:goal, business: book, kind: "other")).not_to be_valid
    expect(build(:goal, business: book, target_cents: 0)).not_to be_valid
    expect(build(:goal, business: book, target: "abc")).not_to be_valid
  end

  it "accepts a payment goal with a full matcher or none at all, not a partial one" do
    expect(build(:goal, business: book)).to be_valid
    expect(build(:goal, business: book, match_field: nil, match_operator: nil, match_value: nil)).to be_valid
    expect(build(:goal, business: book, match_value: "")).not_to be_valid
    expect(build(:goal, business: book, match_operator: "regex")).not_to be_valid
    expect(build(:goal, business: book, match_amount_min: "50", match_amount_max: "10")).not_to be_valid
  end

  it "needs an active, non-credit account in the same book for savings" do
    expect(build(:goal, :savings, business: book)).to be_valid
    expect(build(:goal, :savings, business: book, account: nil)).not_to be_valid
    expect(build(:goal, :savings, business: book, account: create(:account))).not_to be_valid
    expect(build(:goal, :savings, business: book, account: create(:account, business: book, kind: "credit"))).not_to be_valid
    expect(build(:goal, :savings, business: book, account: create(:account, business: book, archived_at: Time.current))).not_to be_valid
  end

  it "lets a savings goal be updated after its account is archived" do
    goal = create(:goal, :savings, business: book)
    goal.account.update!(archived_at: Time.current)
    expect(goal.reload.update(name: "Renamed")).to be(true)
    expect(goal.update(archived_at: Time.current)).to be(true)
  end

  it "rejects retargeting a savings goal to an archived or credit account" do
    goal = create(:goal, :savings, business: book)
    expect(goal.update(account: create(:account, business: book, archived_at: Time.current))).to be(false)
    expect(goal.update(account: create(:account, business: book, kind: "credit"))).to be(false)
  end

  it "is removed when its book is destroyed" do
    create(:goal, :savings, business: book)
    expect { book.destroy }.to change(described_class, :count).by(-1)
    expect(Business.exists?(book.id)).to be(false)
  end

  it "clears fields that don't belong to its kind" do
    savings = create(:goal, :savings, business: book, match_value: "tony", match_field: "payee", match_operator: "contains")
    expect(savings.attributes.values_at("match_field", "match_operator", "match_value")).to all(be_nil)
    payments = create(:goal, business: book, account: create(:account, business: book))
    expect(payments.account_id).to be_nil
  end

  it "does not let the kind change after creation" do
    goal = create(:goal, business: book)
    expect(goal.update(kind: "savings", account: create(:account, business: book))).to be(false)
    expect(goal.errors[:kind]).to be_present
  end

  it "positions new goals last and orders by position" do
    first = create(:goal, business: book)
    second = create(:goal, business: book)
    expect(book.goals.ordered).to eq([ first, second ])
    expect(second.position).to eq(first.position + 1)
  end

  it "exposes its matcher as a rule RuleEngine understands" do
    goal = build(:goal, business: book, match_value: "Tony", match_amount_max: "2,000")
    expect(goal).to be_matcher
    expect(RuleEngine.matches?(goal.matcher_rule, { payee: "ZELLE TONY RUSSO", memo: nil, amount_cents: -1_500_00 })).to be(true)
    expect(RuleEngine.matches?(goal.matcher_rule, { payee: "ZELLE TONY RUSSO", memo: nil, amount_cents: -2_500_00 })).to be(false)
    expect(goal.matcher_description).to eq("payee contains \"Tony\" · ≤ $2,000.00")
    expect(build(:goal, business: book, match_field: nil, match_operator: nil, match_value: nil)).not_to be_matcher
  end
end
