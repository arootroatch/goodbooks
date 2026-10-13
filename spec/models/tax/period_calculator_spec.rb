require "rails_helper"

RSpec.describe Tax::PeriodCalculator do
  def worksheet(profits, businesses: profits.keys.map { tax_business(_1) }, people: businesses.map(&:person_id).uniq.map { tax_person(_1) }, **period)
    described_class.call(params: tax_params_2026, businesses:, people:, period: tax_period(period.delete(:quarter) || 4, profits, **period))
  end

  it "owes nothing on zero profit" do
    result = worksheet({ 1 => 0 })
    expect(result.total_tax_cents).to eq(0)
    expect(result.person_lines.first.se_earnings_cents).to eq(0)
  end

  it "skips SE tax when SE earnings are under $400" do
    # 400.00 × 92.35% = 369.40 < 400 → 0. AGI 400.00 is under the standard deduction.
    result = worksheet({ 1 => 40_000 })
    expect(result.person_lines.first).to have_attributes(se_earnings_cents: 0, ss_cents: 0, medicare_cents: 0)
    expect(result.total_tax_cents).to eq(0)
  end

  it "works a $100,000 single-earner year line by line" do
    # SE earnings 92,350.00; SS 12.4% = 11,451.40; Medicare 2.9% = 2,678.15; half 7,064.775 → 7,064.78
    # AGI 100,000 − 7,064.78 = 92,935.22; before QBI 92,935.22 − 32,200 = 60,735.22
    # QBI 92,935.22; deduction 20% × min(92,935.22, 60,735.22) = 12,147.044 → 12,147.04; taxable 48,588.18
    # tax 2,480.00 + 12% × 23,788.18 (2,854.58) = 5,334.58; total 5,334.58 + 14,129.55 = 19,464.13
    result = worksheet({ 1 => 10_000_000 })
    expect(result.person_lines.first).to have_attributes(se_earnings_cents: 9_235_000, ss_cents: 1_145_140, medicare_cents: 267_815, half_se_cents: 706_478)
    expect(result).to have_attributes(agi_cents: 9_293_522, taxable_before_qbi_cents: 6_073_522, qbi_cents: 9_293_522, qbi_deduction_cents: 1_214_704,
                                      taxable_income_cents: 4_858_818, income_tax_cents: 533_458, additional_medicare_cents: 0)
    expect(result.bracket_slices.map(&:tax_cents)).to eq([ 248_000, 285_458 ])
    expect(result.se_tax_cents).to eq(1_412_955)
    expect(result.total_tax_cents).to eq(1_946_413)
  end

  it "caps Social Security at the wage base" do
    # $250,000: SE earnings 230,875.00; SS 12.4% × 184,500 = 22,878.00; Medicare 2.9% × 230,875 = 6,695.375 → 6,695.38
    result = worksheet({ 1 => 25_000_000 })
    expect(result.person_lines.first).to have_attributes(ss_cents: 2_287_800, medicare_cents: 669_538)
    expect(result.additional_medicare_cents).to eq(0)
    expect(result.total_tax_cents).to eq(5_472_772)
  end

  it "adds Additional Medicare on both spouses' combined SE earnings over $250,000" do
    # 2 × 184,700.00 = 369,400.00; 0.9% × 119,400.00 = 1,074.60
    result = worksheet({ 1 => 20_000_000, 2 => 20_000_000 })
    expect(result.person_lines.map(&:se_earnings_cents)).to eq([ 18_470_000, 18_470_000 ])
    expect(result.additional_medicare_cents).to eq(107_460)
    expect(result.total_tax_cents).to eq(10_793_581)
  end

  it "annualizes a Q2 period by 12/5" do
    # 50,000.00 × 2.4 = 120,000.00
    result = worksheet({ 1 => 5_000_000 }, quarter: 2)
    expect(result.business_lines.first).to have_attributes(ytd_cents: 5_000_000, annualized_cents: 12_000_000)
    expect(result.total_tax_cents).to eq(2_407_440)
  end

  it "annualizes a period in progress by days elapsed" do
    # Apr 20, 2026 is day 110: 22,000.00 × 365/110 = 73,000.00
    result = worksheet({ 1 => 2_200_000 }, quarter: 2, factor: Rational(365, 110), elapsed_days: 110)
    expect(result.business_lines.first.annualized_cents).to eq(7_300_000)
    expect(result.elapsed_days).to eq(110)
    expect(result.total_tax_cents).to eq(1_324_027)
  end

  it "caps the home office at profit and reports the carryover" do
    result = worksheet({ 1 => 100_000 }, businesses: [ tax_business(1, home_office_cents: 150_000) ])
    expect(result.business_lines.first).to have_attributes(home_office_used_cents: 100_000, carryover_cents: 50_000, net_profit_cents: 0)
    expect(result.total_tax_cents).to eq(0)
  end

  it "uses no home office against a loss and never makes SE tax negative" do
    result = worksheet({ 1 => -500_000 }, businesses: [ tax_business(1, home_office_cents: 150_000) ])
    expect(result.business_lines.first).to have_attributes(home_office_used_cents: 0, carryover_cents: 150_000, net_profit_cents: -500_000)
    expect(result.person_lines.first.se_earnings_cents).to eq(0)
    expect(result.total_tax_cents).to eq(0)
  end

  it "offsets a loss against the same person's other business, not the spouse's" do
    # Person 1: 30,000 − 10,000 = 20,000 → SE 18,470.00; person 2: 50,000 → SE 46,175.00
    businesses = [ tax_business(1, person_id: 1), tax_business(2, person_id: 1), tax_business(3, person_id: 2) ]
    result = worksheet({ 1 => 3_000_000, 2 => -1_000_000, 3 => 5_000_000 }, businesses:)
    expect(result.person_lines.map(&:net_profit_cents)).to eq([ 2_000_000, 5_000_000 ])
    expect(result.person_lines.map(&:se_earnings_cents)).to eq([ 1_847_000, 4_617_500 ])
    expect(result.total_tax_cents).to eq(1_254_874)
  end

  it "caps SE health insurance at profit less half SE tax and retirement" do
    # 10,000 profit: half SE 706.48; cap 10,000 − 706.48 = 9,293.52 of 15,000 entered; AGI 0
    result = worksheet({ 1 => 1_000_000 }, people: [ tax_person(1, health: 1_500_000) ])
    expect(result.person_lines.first.health_insurance_cents).to eq(929_352)
    expect(result.agi_cents).to eq(0)
    expect(result.total_tax_cents).to eq(141_296)
  end

  it "subtracts health insurance and retirement from AGI and QBI" do
    # 60,000 profit, half SE 4,238.87, health 9,000, SEP 10,000 → AGI 36,761.13; before QBI 4,561.13;
    # QBI deduction 20% × 4,561.13 = 912.226 → 912.23; taxable 3,648.90; tax 364.89; total 364.89 + 8,477.73
    result = worksheet({ 1 => 6_000_000 }, people: [ tax_person(1, health: 900_000, retirement: 1_000_000, plan: "sep") ])
    expect(result).to have_attributes(agi_cents: 3_676_113, qbi_deduction_cents: 91_223, taxable_income_cents: 364_890, income_tax_cents: 36_489)
    expect(result.total_tax_cents).to eq(884_262)
  end

  it "lists a person with no business with zero SE" do
    result = worksheet({ 1 => 10_000_000 }, people: [ tax_person(1), tax_person(2) ])
    expect(result.person_lines.last).to have_attributes(net_profit_cents: 0, se_earnings_cents: 0, half_se_cents: 0)
  end
end
