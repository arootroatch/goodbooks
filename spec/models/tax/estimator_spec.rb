require "rails_helper"

RSpec.describe Tax::Estimator do
  def estimate(quarter:, **inputs) = described_class.new(tax_inputs(**inputs)).estimate(quarter:)

  def rows(result) = result.installments.map { [ _1.regular_cents, _1.annualized_cents, _1.pay_at_least_cents ] }

  it "uses 90% of projected tax when that is below the safe harbor, and annualized wins early in a lumpy year" do
    # Periods annualize to 40,000 / 48,000 / 90,000: tax 6,049.75 / 7,774.89 / 17,159.00.
    # 90% × 17,159.00 = 15,443.10 < 30,000.00 safe harbor. Paid 2,000 in Q1 and Q2.
    # Regular: 15,443.10 × ¼ − 2,000 = 1,860.78; ×½ − 4,000 = 3,721.55; ×¾ − 4,000 = 7,582.33; ×1 − 4,000 = 11,443.10
    # Annualized: 22.5% × 6,049.75 − 2,000 → 0; 45% × 7,774.89 − 4,000 → 0; 67.5% × 17,159.00 − 4,000 = 7,582.33; Q4 —
    result = estimate(quarter: 3, ytd: { 1 => { 1 => 1_000_000 }, 2 => { 1 => 2_000_000 }, 3 => { 1 => 6_000_000 } },
                      prior_year: Tax::PriorYear.new(total_tax_cents: 3_000_000, agi_cents: 12_000_000),
                      payments: [ Tax::Payment.new(quarter: 1, amount_cents: 200_000), Tax::Payment.new(quarter: 2, amount_cents: 200_000) ])
    expect(result.worksheets.transform_values(&:total_tax_cents)).to eq(1 => 604_975, 2 => 777_489, 3 => 1_715_900)
    expect(result).to have_attributes(ninety_percent_cents: 1_544_310, safe_harbor_cents: 3_000_000, required_annual_cents: 1_544_310)
    expect(rows(result)).to eq([ [ 186_078, 0, 0 ], [ 372_155, 0, 0 ], [ 758_233, 758_233, 758_233 ], [ 1_144_310, nil, 1_144_310 ] ])
    expect(result.installments.map(&:paid_cents)).to eq([ 200_000, 200_000, 0, 0 ])
    expect(result.installments.map(&:paid_through_cents)).to eq([ 200_000, 400_000, 400_000, 400_000 ])
    expect(result.pay_at_least_cents).to eq(758_233)
    expect(result.next_due_on).to eq(Date.new(2026, 9, 15))
  end

  it "uses the 110% safe harbor when prior-year AGI is over $150,000, and regular wins" do
    # 110% × 10,000.00 = 11,000.00 < 90% × 24,074.40 = 21,666.96
    result = estimate(quarter: 2, ytd: { 1 => { 1 => 2_500_000 }, 2 => { 1 => 5_000_000 } },
                      prior_year: Tax::PriorYear.new(total_tax_cents: 1_000_000, agi_cents: 16_000_000))
    expect(result).to have_attributes(ninety_percent_cents: 2_166_696, safe_harbor_cents: 1_100_000, required_annual_cents: 1_100_000)
    expect(rows(result).first(2)).to eq([ [ 275_000, 437_943, 275_000 ], [ 550_000, 1_083_348, 550_000 ] ])
  end

  it "uses 100% at exactly $150,000 prior-year AGI" do
    result = estimate(quarter: 1, ytd: { 1 => { 1 => 2_500_000 } }, prior_year: Tax::PriorYear.new(total_tax_cents: 1_000_000, agi_cents: 15_000_000))
    expect(result.safe_harbor_cents).to eq(1_000_000)
  end

  it "skips the safe harbor and warns when the prior year is missing" do
    result = estimate(quarter: 1, ytd: { 1 => { 1 => 2_500_000 } })
    expect(result.safe_harbor_cents).to be_nil
    expect(result.required_annual_cents).to eq(1_751_772)
    expect(result.warnings.map(&:message)).to include("Enter last year's total tax and AGI to use the safe harbor.")
  end

  it "requires nothing after a year with no tax" do
    result = estimate(quarter: 1, ytd: { 1 => { 1 => 2_500_000 } }, prior_year: Tax::PriorYear.new(total_tax_cents: 0, agi_cents: 5_000_000))
    expect(result.required_annual_cents).to eq(0)
    expect(result.pay_at_least_cents).to eq(0)
  end

  it "floors every installment at zero when payments exceed the requirement" do
    result = estimate(quarter: 1, ytd: { 1 => { 1 => 2_500_000 } }, payments: [ Tax::Payment.new(quarter: 1, amount_cents: 5_000_000) ])
    expect(rows(result)).to eq([ [ 0, 0, 0 ], [ 0, nil, 0 ], [ 0, nil, 0 ], [ 0, nil, 0 ] ])
  end

  it "warns above the QBI threshold" do
    result = estimate(quarter: 4, ytd: { 4 => { 1 => 50_000_000 } })
    expect(result.worksheet.total_tax_cents).to eq(10_970_630)
    expect(result.warnings.map(&:message)).to include(
      "Taxable income is above the QBI threshold ($403,500.00); the simplified QBI deduction may be too high."
    )
  end

  it "warns when a SEP contribution is over 20% of profit less half SE tax" do
    # 60,000 profit: (60,000 − 4,238.87) × 20% = 11,152.226 → 11,152.23 limit; 12,000 entered
    result = estimate(quarter: 4, ytd: { 4 => { 1 => 6_000_000 } }, people: [ tax_person(1, retirement: 1_200_000, plan: "sep") ])
    expect(result.warnings.map(&:message)).to include("Person 1's SEP contribution ($12,000.00) is over the estimated limit ($11,152.23).")
  end

  it "allows a Solo 401(k) the elective deferral on top" do
    # limit min(72,000, 24,500 + 11,152.23) = 35,652.23
    result = estimate(quarter: 4, ytd: { 4 => { 1 => 6_000_000 } }, people: [ tax_person(1, retirement: 3_000_000, plan: "solo_401k") ])
    expect(result.warnings.map(&:kind)).not_to include(:retirement_limit)
  end

  it "warns about a home office carryover" do
    result = estimate(quarter: 4, ytd: { 4 => { 1 => 100_000 } }, businesses: [ tax_business(1, home_office_cents: 150_000) ])
    expect(result.warnings.map(&:message)).to include("Business 1's home office ($1,500.00) is more than its profit; $500.00 carries over.")
  end
end
