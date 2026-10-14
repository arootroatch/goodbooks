require "rails_helper"

RSpec.describe Goals::BalanceHistory do
  let(:today) { Date.new(2026, 10, 14) }

  it "runs forward from the opening balance for manual accounts, newest first" do
    account = create(:account, opening_balance: "1,000", opening_balance_on: Date.new(2026, 1, 1))
    create(:transaction, account: account, posted_on: Date.new(2026, 1, 1), amount_cents: -1_00)
    a = create(:transaction, account: account, posted_on: Date.new(2026, 2, 1), amount_cents: -200_00)
    b = create(:transaction, account: account, posted_on: Date.new(2026, 3, 1), amount_cents: 50_00)
    create(:transaction, account: account, posted_on: Date.new(2026, 3, 2), amount_cents: -5_00, excluded: true)
    expect(described_class.for(account, today:).map { [ _1.txn, _1.balance_cents ] }).to eq([ [ b, 850_00 ], [ a, 800_00 ] ])
  end

  it "runs backward from the reported balance for Plaid accounts over the last 12 months" do
    account = create(:account, :plaid, reported_balance_cents: 1_000_00, balance_reported_at: Time.current)
    create(:transaction, account: account, posted_on: Date.new(2025, 10, 13), amount_cents: -1_00)
    a = create(:transaction, account: account, posted_on: Date.new(2026, 9, 1), amount_cents: -200_00)
    b = create(:transaction, account: account, posted_on: Date.new(2026, 10, 1), amount_cents: 50_00)
    expect(described_class.for(account, today:).map { [ _1.txn, _1.balance_cents ] }).to eq([ [ b, 1_000_00 ], [ a, 950_00 ] ])
  end

  it "is empty when the balance is unknown" do
    expect(described_class.for(create(:account), today:)).to eq([])
  end
end
