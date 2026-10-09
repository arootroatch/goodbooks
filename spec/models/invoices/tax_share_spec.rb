require "rails_helper"

RSpec.describe Invoices::TaxShare do
  def call(payment, paid_before: 0, shares_before: 0, amount: 10_000, tax: 1_000)
    described_class.call(invoice_amount_cents: amount, invoice_tax_cents: tax, paid_before_cents: paid_before,
                         shares_before_cents: shares_before, payment_cents: payment)
  end

  it "gives a full payment the whole tax" do
    expect(call(10_000)).to eq(1_000)
  end

  it "pro-rates partial payments and lets the last one absorb rounding" do
    expect(call(3_333)).to eq(333)
    expect(call(3_333, paid_before: 3_333, shares_before: 333)).to eq(333)
    expect(call(3_334, paid_before: 6_666, shares_before: 666)).to eq(334)
  end

  it "is zero for an untaxed invoice" do
    expect(call(5_000, tax: 0)).to eq(0)
  end
end
