require "rails_helper"

RSpec.describe Reports::Spending do
  def row(month, name, kind, cents) = described_class::Row.new(month: month, category_name: name, kind: kind, sum_cents: cents)

  it "lists the months a range touches" do
    expect(described_class.months_in(Date.new(2026, 1, 15)..Date.new(2026, 3, 1))).to eq(%w[2026-01 2026-02 2026-03])
  end

  it "builds income and expense grids, expenses shown positive, with totals and net" do
    report = described_class.new([ row("2026-01", "Groceries", "expense", -30_000), row("2026-02", "Groceries", "expense", -20_000),
                                   row("2026-02", "Groceries", "expense", 1_000), row("2026-01", "Owner draws", "income", 600_000) ],
                                 months: %w[2026-01 2026-02])
    groceries = report.expense_lines.sole
    expect(groceries.amounts).to eq("2026-01" => 30_000, "2026-02" => 19_000)
    expect(groceries.total_cents).to eq(49_000)
    expect(report.income_total.amounts).to eq("2026-01" => 600_000, "2026-02" => 0)
    expect(report.net.amounts).to eq("2026-01" => 570_000, "2026-02" => -19_000)
    expect(report.net.total_cents).to eq(551_000)
  end

  it "loads grouped sums for one book" do
    book = create(:business, :personal)
    account = create(:account, business: book)
    groceries = create(:category, business: book, name: "Groceries")
    create(:transaction, account: account, category: groceries, amount_cents: -1_000, posted_on: Date.new(2026, 1, 5))
    create(:transaction, account: account, category: groceries, amount_cents: -2_000, posted_on: Date.new(2026, 1, 20))
    create(:transaction, account: account, category: groceries, amount_cents: -9_000, posted_on: Date.new(2026, 1, 21), transfer: false, excluded: true)
    rows = described_class.load(business_id: book.id, range: Date.new(2026, 1, 1)..Date.new(2026, 1, 31))
    expect(rows).to eq([ described_class::Row.new(month: "2026-01", category_name: "Groceries", kind: "expense", sum_cents: -3_000) ])
  end
end
