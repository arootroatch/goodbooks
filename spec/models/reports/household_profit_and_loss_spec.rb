require "rails_helper"

RSpec.describe Reports::HouseholdProfitAndLoss do
  let(:fake_business_class) { Struct.new(:id, :name) }

  def pnl(*totals, mileage: 0)
    Reports::ProfitAndLoss.new(category_totals: totals, mileage_deduction_cents: mileage)
  end

  def total(business_id, name, kind, sum)
    Reports::CategoryTotal.new(business_id:, category_id: 0, name:, kind:, schedule_c_line: kind == "income" ? "1" : "18", deductible_bps: 10_000, sum_cents: sum)
  end

  let(:pat) { fake_business_class.new(1, "Pat") }
  let(:jordan) { fake_business_class.new(2, "Jordan") }
  let(:report) do
    described_class.new(
      pat => pnl(total(1, "Sales", "income", 100_00), total(1, "Office", "expense", -10_00), mileage: 5_00),
      jordan => pnl(total(2, "Sales", "income", 50_00), total(2, "Supplies", "expense", -2_00))
    )
  end

  it "aligns rows by category name across businesses" do
    expect(report.income_rows.map { [ _1.name, _1.amounts, _1.total_cents ] }).to eq([ [ "Sales", { 1 => 100_00, 2 => 50_00 }, 150_00 ] ])
    expect(report.expense_rows.map { [ _1.name, _1.amounts, _1.total_cents ] }).to eq([
      [ "Office", { 1 => 10_00 }, 10_00 ], [ "Supplies", { 2 => 2_00 }, 2_00 ]
    ])
  end

  it "computes a summary column per business plus a total" do
    expect(report.column(:net_profit_cents)).to eq(1 => 85_00, 2 => 48_00, total: 133_00)
  end
end
