require "rails_helper"

RSpec.describe PlaidFeed::TransactionMapper do
  def plaid(**overrides)
    { transaction_id: "t-1", account_id: "a-1", amount: 12.34, date: Date.new(2026, 10, 1),
      name: "SQ *JOES COFFEE 8475", merchant_name: "Joe's Coffee", pending: false }.merge(overrides)
  end

  it "inverts the sign: Plaid outflows are positive, the app's are negative" do
    expect(described_class.call(plaid(amount: 12.34)).amount_cents).to eq(-1234)
    expect(described_class.call(plaid(amount: -250.0)).amount_cents).to eq(25_000)
  end

  it "converts float amounts to exact cents" do
    { 1234.5 => -123_450, 19.99 => -1999, 0.1 => -10, 0.07 => -7, 1_000_000.01 => -100_000_001 }.each do |amount, cents|
      expect(described_class.call(plaid(amount: amount)).amount_cents).to eq(cents), amount.to_s
    end
  end

  it "raises on a fraction of a cent instead of rounding" do
    expect { described_class.call(plaid(amount: 12.345)) }.to raise_error(described_class::InvalidAmount, /12.345/)
  end

  it "uses the merchant name as payee and keeps the raw name as memo" do
    row = described_class.call(plaid)
    expect(row.payee).to eq("Joe's Coffee")
    expect(row.memo).to eq("SQ *JOES COFFEE 8475")
  end

  it "falls back to the name, then Unknown, and squishes whitespace" do
    row = described_class.call(plaid(merchant_name: nil, name: "  ACH   DEPOSIT  "))
    expect(row.payee).to eq("ACH DEPOSIT")
    expect(row.memo).to be_nil
    expect(described_class.call(plaid(merchant_name: "", name: "")).payee).to eq("Unknown")
    expect(described_class.call(plaid(merchant_name: "Kroger", name: "Kroger")).memo).to be_nil
  end

  it "skips pending transactions" do
    expect(described_class.call(plaid(pending: true))).to be_nil
  end

  it "accepts ISO date strings and returns the attributes to save" do
    row = described_class.call(plaid(date: "2026-10-02"))
    expect(row.posted_on).to eq(Date.new(2026, 10, 2))
    expect(row.plaid_account_id).to eq("a-1")
    expect(row.attributes).to eq(plaid_transaction_id: "t-1", posted_on: Date.new(2026, 10, 2), amount_cents: -1234,
                                 payee: "Joe's Coffee", memo: "SQ *JOES COFFEE 8475")
  end
end
