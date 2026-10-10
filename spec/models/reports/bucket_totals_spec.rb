require "rails_helper"

RSpec.describe Reports::BucketTotals do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }
  let(:income) { create(:category, :income, business: business) }
  let(:expense) { create(:category, business: business) }
  let(:buckets) do
    [ Period::Bucket.new(label: "Feb 1", range: Date.new(2026, 2, 1)..Date.new(2026, 2, 7)),
      Period::Bucket.new(label: "Feb 8", range: Date.new(2026, 2, 8)..Date.new(2026, 2, 14)) ]
  end

  def totals(business_ids: [ business.id ]) = described_class.load(business_ids:, buckets:)

  it "returns one zero-filled row per bucket" do
    expect(totals.map(&:label)).to eq([ "Feb 1", "Feb 8" ])
    expect(totals.map(&:income_cents)).to eq([ 0, 0 ])
    expect(totals.map(&:expense_cents)).to eq([ 0, 0 ])
  end

  it "sums income and expense per bucket as positive magnitudes, including both edge days" do
    create(:transaction, account:, category: income, posted_on: Date.new(2026, 2, 1), amount_cents: 400_000)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 2, 7), amount_cents: -5_499)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 2, 8), amount_cents: -1_000)
    expect(totals.first).to have_attributes(income_cents: 400_000, expense_cents: 5_499)
    expect(totals.last).to have_attributes(income_cents: 0, expense_cents: 1_000)
  end

  it "ignores uncategorized, transfer, and excluded transactions" do
    create(:transaction, account:, category: nil, posted_on: Date.new(2026, 2, 2), amount_cents: -100)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 2, 2), amount_cents: -200, excluded: true)
    create(:transaction, account:, transfer: true, posted_on: Date.new(2026, 2, 2), amount_cents: -300)
    expect(totals.first.expense_cents).to eq(0)
  end

  it "ignores dates outside the buckets and other businesses" do
    other_account = create(:account, business: create(:business))
    other_expense = create(:category, business: other_account.business)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 1, 31), amount_cents: -100)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 2, 15), amount_cents: -100)
    create(:transaction, account: other_account, category: other_expense, posted_on: Date.new(2026, 2, 2), amount_cents: -100)
    expect(totals.sum(&:expense_cents)).to eq(0)
  end

  it "handles no buckets" do
    expect(described_class.load(business_ids: [ business.id ], buckets: [])).to eq([])
  end
end
