require "rails_helper"

RSpec.describe RuleApplier do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }
  let(:software) { create(:category, business: business, name: "Software") }
  let!(:rule) { create(:rule, business: business, value: "adobe", category: software) }
  let!(:transfer_rule) { create(:rule, business: business, value: "card payment", outcome: "transfer", category: nil) }

  it "categorizes matching inbox transactions and records the rule" do
    txn = create(:transaction, account: account, payee: "ADOBE *CC")
    expect(RuleApplier.new(business).apply([txn])).to eq(1)
    txn.reload
    expect(txn.category).to eq(software)
    expect(txn.categorized_by).to eq("rule")
    expect(txn.rule).to eq(rule)
  end

  it "marks transfers" do
    txn = create(:transaction, account: account, payee: "Card payment thank you")
    RuleApplier.new(business).apply([txn])
    expect(txn.reload).to be_transfer
  end

  it "never overrides a user's choice, even an uncategorized one" do
    other = create(:category, business: business, name: "Other")
    chosen = create(:transaction, account: account, payee: "ADOBE", category: other, categorized_by: "user")
    cleared = create(:transaction, account: account, payee: "ADOBE", categorized_by: "user")
    expect(RuleApplier.new(business).apply([chosen, cleared])).to eq(0)
    expect(chosen.reload.category).to eq(other)
    expect(cleared.reload.category).to be_nil
  end

  it "leaves non-matching transactions alone" do
    txn = create(:transaction, account: account, payee: "Coffee")
    expect(RuleApplier.new(business).apply([txn])).to eq(0)
    expect(txn.reload).to be_inbox
  end

  it "nullifies the transaction's rule when the rule is deleted" do
    txn = create(:transaction, account: account, payee: "ADOBE")
    RuleApplier.new(business).apply([txn])
    rule.destroy!
    expect(txn.reload.rule_id).to be_nil
    expect(txn.category).to eq(software)
  end
end
