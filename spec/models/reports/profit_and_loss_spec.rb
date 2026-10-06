require "rails_helper"

RSpec.describe Reports::ProfitAndLoss do
  def total(name, kind, sum, line: kind == "income" ? "1" : "18", bps: 10_000)
    Reports::CategoryTotal.new(business_id: 1, category_id: name.hash, name:, kind:, schedule_c_line: line, deductible_bps: bps, sum_cents: sum)
  end

  let(:report) do
    described_class.new(category_totals: [
      total("Sales", "income", 1_000_000),
      total("Refunds given", "income", -5_000, line: "2"),
      total("Office", "expense", -20_000),
      total("Meals", "expense", -3_333, line: "24b", bps: 5000),
      total("Software", "expense", 1_000)
    ], mileage_deduction_cents: 8_947)
  end

  it "keeps income signed" do
    expect(report.income_lines.map { [_1.name, _1.actual_cents] }).to eq([["Refunds given", -5_000], ["Sales", 1_000_000]])
    expect(report.total_income_cents).to eq(995_000)
  end

  it "shows expenses positive, with refunds reducing them" do
    expect(report.expense_lines.map { [_1.name, _1.actual_cents] }).to eq([["Meals", 3_333], ["Office", 20_000], ["Software", -1_000]])
  end

  it "applies deductible percentages, rounding half up once per line" do
    meals = report.expense_lines.find { _1.name == "Meals" }
    expect(meals.deductible_cents).to eq(1_667)
    expect(report.total_expense_cents).to eq(22_333)
    expect(report.total_deductible_expense_cents).to eq(20_667)
  end

  it "subtracts deductible expenses and mileage from income" do
    expect(report.net_profit_cents).to eq(995_000 - 20_667 - 8_947)
  end
end
