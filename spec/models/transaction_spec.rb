require "rails_helper"

RSpec.describe Transaction do
  let(:account) { create(:account) }

  it "parses the amount and applies the direction" do
    txn = Transaction.create!(account: account, posted_on: Date.current, payee: "Cash supplies", amount: "$12.50", direction: "out")
    expect(txn.amount_cents).to eq(-1250)
    txn.update!(amount: "-3", direction: "in")
    expect(txn.amount_cents).to eq(300)
  end

  it "reports a garbage amount instead of saving zero" do
    txn = Transaction.new(account: account, posted_on: Date.current, payee: "X", amount: "12a")
    expect(txn).not_to be_valid
    expect(txn.errors.full_messages).to eq([ "Amount is not a valid amount" ])
  end

  it "reports a blank amount with a single error" do
    txn = Transaction.new(account: account, posted_on: Date.current, payee: "X", amount: "")
    expect(txn).not_to be_valid
    expect(txn.errors.full_messages).to eq([ "Amount can't be blank" ])
  end

  it "requires a category from the same business" do
    foreign = create(:category)
    txn = build(:transaction, account: account, category: foreign)
    expect(txn).not_to be_valid
    expect(txn.errors[:category]).to include("must belong to this business")
  end

  it "clears the category when marked as a transfer" do
    category = create(:category, business: account.business)
    txn = create(:transaction, account: account, category: category)
    txn.update!(transfer: true)
    expect(txn.category).to be_nil
  end

  describe "scopes" do
    let!(:inbox) { create(:transaction, account: account) }
    let!(:categorized) { create(:transaction, account: account, category: create(:category, business: account.business)) }
    let!(:transfer) { create(:transaction, account: account, transfer: true) }
    let!(:excluded) { create(:transaction, account: account, excluded: true) }

    it "inbox = uncategorized, not transfer, not excluded" do
      expect(Transaction.inbox).to contain_exactly(inbox)
      expect(inbox).to be_inbox
    end

    it "countable excludes transfers and excluded" do
      expect(Transaction.countable).to contain_exactly(inbox, categorized)
    end

    it "for_businesses filters by the account's business" do
      create(:transaction)
      expect(Transaction.for_businesses([ account.business_id ]).count).to eq(4)
    end
  end

  it "exposes the attributes rules match on" do
    txn = build(:transaction, payee: "ADOBE", memo: "CC", amount_cents: -5499)
    expect(txn.rule_attributes).to eq(payee: "ADOBE", memo: "CC", amount_cents: -5499)
  end
end
