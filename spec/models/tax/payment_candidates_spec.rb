require "rails_helper"

RSpec.describe Tax::PaymentCandidates do
  let(:business) { create(:business) }
  let(:user) { user_with_role("owner", business) }
  let(:account) { create(:account, business:) }

  def debit(payee, on, cents = -10_000, to: account) = create(:transaction, account: to, payee:, posted_on: on, amount_cents: cents)

  it "lists money out in the window, IRS payees first, then newest" do
    groceries = debit("KROGER", Date.new(2026, 6, 20))
    irs = debit("IRS USATAXPYMT", Date.new(2026, 4, 14))
    eftps = debit("eftps payment", Date.new(2026, 1, 2))
    january = debit("RENT", Date.new(2027, 1, 31))
    debit("TOO EARLY", Date.new(2025, 12, 31))
    debit("TOO LATE", Date.new(2027, 2, 1))
    debit("DEPOSIT", Date.new(2026, 5, 1), 10_000)
    expect(described_class.for(user:, year: 2026).to_a).to eq([ irs, eftps, january, groceries ])
  end

  it "filters by payee" do
    irs = debit("IRS USATAXPYMT", Date.new(2026, 4, 14))
    debit("KROGER", Date.new(2026, 6, 20))
    expect(described_class.for(user:, year: 2026, query: "usatax").to_a).to eq([ irs ])
  end

  it "treats % and _ in the search as text" do
    debit("KROGER", Date.new(2026, 6, 20))
    expect(described_class.for(user:, year: 2026, query: "%").to_a).to eq([])
  end

  it "drops debits already recorded" do
    recorded = debit("IRS USATAXPYMT", Date.new(2026, 4, 14))
    create(:estimated_payment, debit: recorded, amount_cents: 10_000)
    expect(described_class.for(user:, year: 2026).to_a).to eq([])
  end

  it "only sees the user's books" do
    debit("IRS USATAXPYMT", Date.new(2026, 4, 14), to: create(:account, business: create(:business)))
    expect(described_class.for(user:, year: 2026).to_a).to eq([])
  end
end
