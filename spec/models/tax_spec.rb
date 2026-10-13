require "rails_helper"

RSpec.describe Tax do
  let!(:household) { create(:household) }

  it "is nil without estimate-ready parameters" do
    expect(described_class.estimate(household:, year: 2026)).to be_nil
    create(:tax_parameters, year: 2026)
    expect(described_class.estimate(household:, year: 2026)).to be_nil
  end

  it "estimates the current installment by default" do
    create(:tax_parameters, :federal_2026)
    estimate = described_class.estimate(household:, year: 2026, today: Date.new(2026, 5, 1))
    expect(estimate.quarter).to eq(2)
    expect(estimate.next_due_on).to eq(Date.new(2026, 6, 15))
  end

  it "picks Q1 for a year that hasn't started and Q4 for one that has ended" do
    expect(described_class.default_quarter(2027, Date.new(2026, 10, 12))).to eq(1)
    expect(described_class.default_quarter(2025, Date.new(2026, 10, 12))).to eq(4)
  end
end
