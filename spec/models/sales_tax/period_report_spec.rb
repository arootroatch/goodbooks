require "rails_helper"

RSpec.describe SalesTax::PeriodReport do
  let(:period) do
    SalesTax::Calendar::Period.new(starts_on: Date.new(2026, 4, 1), ends_on: Date.new(2026, 6, 30), due_on: Date.new(2026, 7, 20))
  end
  let(:deposits) do
    [
      described_class::Deposit.new(posted_on: Date.new(2026, 4, 1), treatment: "taxable", gross_cents: 100_000, total_tax_cents: 8_467),
      described_class::Deposit.new(posted_on: Date.new(2026, 6, 30), treatment: "exempt", gross_cents: 50_000, total_tax_cents: 0),
      described_class::Deposit.new(posted_on: Date.new(2026, 7, 1), treatment: "taxable", gross_cents: 99_999, total_tax_cents: 999),
      described_class::Deposit.new(posted_on: Date.new(2026, 3, 31), treatment: "taxable", gross_cents: 99_999, total_tax_cents: 999)
    ]
  end
  let(:remittances) do
    [
      described_class::Remittance.new(posted_on: Date.new(2026, 7, 15), amount_cents: -8_000, period_starts_on: Date.new(2026, 4, 1)),
      described_class::Remittance.new(posted_on: Date.new(2026, 5, 15), amount_cents: -9_999, period_starts_on: Date.new(2026, 1, 1))
    ]
  end
  let(:filing) { Object.new }

  def report(today:, filing: nil, remitted: remittances)
    described_class.new(period: period, deposits: deposits, remittances: remitted, filing: filing, today: today)
  end

  it "computes every figure from the period's own deposits and remittances" do
    r = report(today: Date.new(2026, 7, 16))
    expect(r.gross_sales_cents).to eq(150_000)
    expect(r.exempt_sales_cents).to eq(50_000)
    expect(r.taxable_sales_cents).to eq(91_533)
    expect(r.tax_collected_cents).to eq(8_467)
    expect(r.remitted_cents).to eq(8_000)
    expect(r.balance_cents).to eq(467)
    expect(r.deposits.size).to eq(2)
    expect(r.remittances.size).to eq(1)
  end

  it "derives the status" do
    expect(report(today: Date.new(2026, 6, 30)).status).to eq("open")
    expect(report(today: Date.new(2026, 7, 1)).status).to eq("due")
    expect(report(today: Date.new(2026, 7, 20)).status).to eq("due")
    expect(report(today: Date.new(2026, 7, 21)).status).to eq("overdue")
    expect(report(today: Date.new(2026, 7, 21), filing: filing).status).to eq("filed")
    paid = [ described_class::Remittance.new(posted_on: Date.new(2026, 7, 15), amount_cents: -8_467, period_starts_on: period.starts_on) ]
    expect(report(today: Date.new(2026, 7, 21), filing: filing, remitted: paid)).to be_paid
  end

  it "treats an overpayment as paid with a negative balance" do
    over = [ described_class::Remittance.new(posted_on: Date.new(2026, 7, 15), amount_cents: -9_000, period_starts_on: period.starts_on) ]
    r = report(today: Date.new(2026, 7, 21), filing: filing, remitted: over)
    expect(r.balance_cents).to eq(-533)
    expect(r.status).to eq("paid")
  end
end
