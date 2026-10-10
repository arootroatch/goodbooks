require "rails_helper"

RSpec.describe InvoicePayment do
  let(:invoice) { create(:invoice) }

  it "requires a positive amount" do
    expect(build(:invoice_payment, invoice: invoice, amount_cents: 0)).not_to be_valid
    expect(build(:invoice_payment, invoice: invoice, amount_cents: -5)).not_to be_valid
  end

  it "requires the deposit to be in the invoice's business" do
    foreign = create(:transaction, amount_cents: 120_000)
    payment = build(:invoice_payment, invoice: invoice, deposit: foreign)
    expect(payment).not_to be_valid
    expect(payment.errors[:deposit]).to include("must belong to the invoice's business")
  end

  it "links a deposit to an invoice at most once" do
    payment = create(:invoice_payment, invoice: invoice, amount_cents: 10_000)
    expect(build(:invoice_payment, invoice: invoice, deposit: payment.deposit, amount_cents: 10_000)).not_to be_valid
  end
end
