require "rails_helper"

RSpec.describe Invoices::Allocation do
  def call(requested = nil, invoice: 120_000, paid: 0, deposit: 120_000, allocated: 0)
    described_class.call(invoice_amount_cents: invoice, invoice_paid_cents: paid,
                         deposit_amount_cents: deposit, deposit_allocated_cents: allocated, requested_cents: requested)
  end

  it "proposes the full amount for an exact match" do
    result = call
    expect(result).to be_ok
    expect(result.amount_cents).to eq(120_000)
  end

  it "proposes the invoice's outstanding balance when the deposit is larger" do
    expect(call(invoice: 120_000, paid: 20_000, deposit: 500_000).amount_cents).to eq(100_000)
  end

  it "proposes the deposit's unallocated amount when the invoice is larger" do
    expect(call(invoice: 300_000, deposit: 100_000, allocated: 40_000).amount_cents).to eq(60_000)
  end

  it "accepts a smaller requested amount (partial payment)" do
    expect(call(50_000).amount_cents).to eq(50_000)
  end

  it "accepts a request equal to both limits" do
    expect(call(120_000)).to be_ok
  end

  it "rejects a fully paid invoice" do
    expect(call(paid: 120_000).error).to eq("This invoice is already fully paid.")
  end

  it "rejects a fully allocated deposit" do
    expect(call(allocated: 120_000).error).to eq("This deposit is already fully allocated.")
  end

  it "rejects zero and negative requests" do
    expect(call(0).error).to eq("Amount must be greater than zero.")
    expect(call(-5).error).to eq("Amount must be greater than zero.")
  end

  it "rejects a request above the invoice's outstanding balance" do
    expect(call(100_001, invoice: 100_000, deposit: 500_000).error)
      .to eq("Amount can't exceed the invoice's outstanding $1,000.00.")
  end

  it "rejects a request above the deposit's unallocated amount" do
    expect(call(90_000, invoice: 500_000, deposit: 100_000, allocated: 20_000).error)
      .to eq("Amount can't exceed the deposit's unallocated $800.00.")
  end
end
