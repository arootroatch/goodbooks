require "rails_helper"

RSpec.describe Tax::Estimate do
  def installment(quarter, due_on, paid_cents: 0, regular_cents: 0)
    Tax::Estimate::Installment.new(quarter:, due_on:, regular_cents:, annualized_cents: nil, paid_cents:, paid_through_cents: 0)
  end

  def estimate(required_annual_cents:, installments:)
    described_class.new(year: 2026, quarter: 2, worksheets: {}, ninety_percent_cents: required_annual_cents, safe_harbor_cents: nil,
                        required_annual_cents:, installments:, warnings: [])
  end

  let(:dues) { [ Date.new(2026, 4, 15), Date.new(2026, 6, 15), Date.new(2026, 9, 15), Date.new(2027, 1, 15) ] }

  it "totals the payments across every quarter" do
    est = estimate(required_annual_cents: 1_000_000, installments: dues.each_with_index.map { |d, i| installment(i + 1, d, paid_cents: 100_000) })
    expect(est.paid_cents).to eq(400_000)
    expect(est.paid_percent).to eq(40)
  end

  it "rounds the percent down and caps it at 100" do
    expect(estimate(required_annual_cents: 300_000, installments: [ installment(1, dues[0], paid_cents: 199_999) ]).paid_percent).to eq(66)
    expect(estimate(required_annual_cents: 100_000, installments: [ installment(1, dues[0], paid_cents: 250_000) ]).paid_percent).to eq(100)
  end

  it "counts nothing required as fully paid" do
    expect(estimate(required_annual_cents: 0, installments: [ installment(1, dues[0]) ]).paid_percent).to eq(100)
  end

  describe Tax::Estimate::Installment do
    it "is past due once its due date has passed with money still owed" do
      expect(installment(1, Date.new(2026, 4, 15), regular_cents: 5_000).past_due?(Date.new(2026, 4, 16))).to be(true)
    end

    it "is not past due on the due date itself or when nothing is owed" do
      expect(installment(1, Date.new(2026, 4, 15), regular_cents: 5_000).past_due?(Date.new(2026, 4, 15))).to be(false)
      expect(installment(1, Date.new(2026, 4, 15), regular_cents: 0).past_due?(Date.new(2026, 5, 1))).to be(false)
    end
  end
end
