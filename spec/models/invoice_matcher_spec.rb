require "rails_helper"

RSpec.describe InvoiceMatcher do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }

  it "matches open invoices by exact outstanding balance in the same business, oldest due first, at most three" do
    due_dates = [ 10, 5, 20, 15 ].map { Date.new(2026, 3, _1) }
    invoices = due_dates.map { create(:invoice, business: business, amount_cents: 50_000, due_date: _1) }
    create(:invoice, business: business, amount_cents: 50_000, status: "draft")
    create(:invoice, amount_cents: 50_000)
    deposit = create(:transaction, account: account, amount_cents: 50_000)

    matches = described_class.for_businesses([ business.id ]).for(deposit, business.id)
    expect(matches).to eq(invoices.values_at(1, 0, 3))
  end

  it "uses the outstanding balance, not the invoice amount" do
    invoice = create(:invoice, business: business, amount_cents: 80_000)
    create(:invoice_payment, invoice: invoice, amount_cents: 30_000)
    matcher = described_class.for_businesses([ business.id ])
    expect(matcher.for(create(:transaction, account: account, amount_cents: 50_000), business.id)).to eq([ invoice ])
    expect(matcher.for(create(:transaction, account: account, amount_cents: 80_000), business.id)).to eq([])
  end

  it "never matches money out" do
    create(:invoice, business: business, amount_cents: 1_000)
    expect(described_class.for_businesses([ business.id ]).for(create(:transaction, account: account, amount_cents: -1_000), business.id)).to eq([])
  end

  it "matches on the deposit's gross, so a fee-reduced payout matches its invoice" do
    invoice = create(:invoice, business: business, amount_cents: 100_000)
    payout = create(:transaction, account: account, amount_cents: 97_070, processor_fee_cents: 2_930)
    expect(described_class.for_businesses([ business.id ]).for(payout, business.id)).to eq([ invoice ])
  end
end
