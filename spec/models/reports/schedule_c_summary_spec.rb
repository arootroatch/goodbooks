require "rails_helper"

RSpec.describe Reports::ScheduleCSummary do
  def total(name, kind, sum, line, bps: 10_000)
    Reports::CategoryTotal.new(business_id: 1, category_id: name.hash, name:, kind:, schedule_c_line: line, deductible_bps: bps, sum_cents: sum)
  end

  let(:summary) do
    described_class.new(category_totals: [
      total("Sales", "income", 500_000, "1"),
      total("Software", "expense", -10_000, "27a"),
      total("Phone", "expense", -5_000, "27a"),
      total("Meals", "expense", -2_001, "24b", bps: 5000),
      total("Parking", "expense", -1_500, "9")
    ], mileage_deduction_cents: 10_000)
  end

  it "groups by line in Schedule C order, combining mileage into line 9" do
    expect(summary.lines).to eq("1" => 500_000, "9" => 11_500, "24b" => 1_001, "27a" => 15_000)
  end

  it "totals" do
    expect(summary.gross_income_cents).to eq(500_000)
    expect(summary.total_expenses_cents).to eq(27_501)
    expect(summary.net_profit_cents).to eq(472_499)
  end

  it "adds a line 9 for mileage alone" do
    only_mileage = described_class.new(category_totals: [], mileage_deduction_cents: 500)
    expect(only_mileage.lines).to eq("9" => 500)
  end
end
