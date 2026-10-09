require "rails_helper"

RSpec.describe Transaction, "linked to an invoice" do
  let(:payment) { create(:invoice_payment, invoice: create(:invoice, number: "INV-1042"), amount_cents: 120_000) }
  let(:deposit) { payment.deposit }
  let(:business) { deposit.business }
  let(:message) { "Linked to INV-1042 — unlink the payment first." }

  it "can't move to an expense category, be a transfer, or be excluded" do
    expense = create(:category, business: business)
    [ { category: expense }, { transfer: true }, { excluded: true } ].each do |attrs|
      expect(deposit.reload.update(attrs)).to be(false), "accepted #{attrs.keys.first}"
      expect(deposit.errors[:base]).to include(message)
    end
  end

  it "can move to another income category" do
    other_income = create(:category, :income, business: business, name: "Other income", schedule_c_line: "6")
    expect(deposit.update(category: other_income)).to be(true)
  end

  it "can't drop below the amount already allocated" do
    expect(deposit.update(amount_cents: 119_999)).to be(false)
    expect(deposit.errors[:base]).to include(message)
  end

  it "can't be destroyed" do
    expect(deposit.destroy).to be(false)
    expect(Transaction.exists?(deposit.id)).to be(true)
  end

  it "re-dates the paid invoice when its date changes" do
    payment.invoice.sync_payment_status!
    deposit.update!(posted_on: Date.new(2026, 4, 2))
    expect(payment.invoice.reload.paid_on).to eq(Date.new(2026, 4, 2))
  end

  it "reports allocated and unallocated cents" do
    expect(deposit.allocated_cents).to eq(120_000)
    expect(deposit.unallocated_cents).to eq(0)
  end

  it "counts the processor fee toward the unallocated amount" do
    deposit.update!(processor_fee_cents: 500)
    expect(deposit.unallocated_cents).to eq(500)
    expect(Transaction.linkable_deposits).to include(deposit)
    expect(deposit.update(processor_fee_cents: 0)).to be(true)
    expect(deposit.update(amount_cents: 119_000, processor_fee_cents: 999)).to be(false)
  end
end

RSpec.describe Transaction, ".linkable_deposits" do
  let(:account) { create(:account) }
  let(:business) { account.business }
  let(:income) { create(:category, :income, business: business) }

  it "keeps positive, countable, uncategorized-or-income deposits with money left to allocate" do
    uncategorized = create(:transaction, account: account, amount_cents: 5_000)
    income_deposit = create(:transaction, account: account, amount_cents: 5_000, category: income)
    create(:transaction, account: account, amount_cents: -5_000)
    create(:transaction, account: account, amount_cents: 5_000, transfer: true)
    create(:transaction, account: account, amount_cents: 5_000, excluded: true)
    create(:transaction, account: account, amount_cents: 5_000, category: create(:category, business: business))
    invoice = create(:invoice, business: business, amount_cents: 5_000)
    full = create(:invoice_payment, invoice: invoice, amount_cents: 5_000).deposit
    partial = create(:invoice_payment, invoice: create(:invoice, business: business, amount_cents: 9_000), amount_cents: 3_000).deposit

    expect(Transaction.linkable_deposits).to contain_exactly(uncategorized, income_deposit, partial)
    expect(Transaction.linkable_deposits.with_unallocated(6_000)).to eq([ partial ])
    expect(full.unallocated_cents).to eq(0)
  end
end
