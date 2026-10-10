require "rails_helper"

RSpec.describe Reports::MonthlyTotals do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }
  let(:income) { create(:category, :income, business: business) }
  let(:expense) { create(:category, business: business) }

  def totals(through_month: 3, year: 2026, business_ids: [ business.id ])
    described_class.load(business_ids:, year:, through_month:)
  end

  it "returns one zero-filled row per month through the given month" do
    expect(totals.map(&:month)).to eq([ 1, 2, 3 ])
    expect(totals.map(&:income_cents)).to eq([ 0, 0, 0 ])
    expect(totals.map(&:expense_cents)).to eq([ 0, 0, 0 ])
  end

  it "sums income and expense per month as positive magnitudes" do
    create(:transaction, account:, category: income, posted_on: Date.new(2026, 2, 3), amount_cents: 400_000)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 2, 9), amount_cents: -5_499)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 2, 28), amount_cents: -1_000)
    expect(totals(through_month: 2).last).to have_attributes(month: 2, income_cents: 400_000, expense_cents: 6_499)
  end

  it "ignores uncategorized, transfer, and excluded transactions" do
    create(:transaction, account:, category: nil, posted_on: Date.new(2026, 1, 5), amount_cents: -100)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 1, 5), amount_cents: -200, excluded: true)
    create(:transaction, account:, transfer: true, posted_on: Date.new(2026, 1, 5), amount_cents: -300)
    expect(totals(through_month: 1).first.expense_cents).to eq(0)
  end

  it "ignores other years, later months, and other businesses" do
    other_account = create(:account, business: create(:business))
    other_expense = create(:category, business: other_account.business)
    create(:transaction, account:, category: expense, posted_on: Date.new(2025, 1, 5), amount_cents: -100)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 4, 1), amount_cents: -100)
    create(:transaction, account: other_account, category: other_expense, posted_on: Date.new(2026, 1, 5), amount_cents: -100)
    expect(totals(through_month: 3).sum(&:expense_cents)).to eq(0)
  end

  it "includes the last day of the final month" do
    create(:transaction, account:, category: income, posted_on: Date.new(2026, 2, 28), amount_cents: 100)
    expect(totals(through_month: 2).last.income_cents).to eq(100)
  end
end
