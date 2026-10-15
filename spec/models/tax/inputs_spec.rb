require "rails_helper"

RSpec.describe Tax::Inputs do
  let!(:household) { create(:household) }
  let(:person) { create(:person, household:) }
  let(:business) { create(:business, household:, person:) }
  let(:account) { create(:account, business:) }
  let(:income) { create(:category, :income, business:) }
  let(:tax_parameters) { create(:tax_parameters, :federal_2026) }

  def load(today) = described_class.load(household:, year: 2026, tax_parameters:, today:)

  def deposit(on, cents, category: income, to: account) = create(:transaction, account: to, category:, posted_on: on, amount_cents: cents)

  it "takes YTD profit for each ended period with the Schedule AI factors" do
    deposit(Date.new(2026, 3, 31), 100_000)
    deposit(Date.new(2026, 4, 1), 50_000)
    deposit(Date.new(2026, 9, 1), 7_000)
    inputs = load(Date.new(2026, 9, 1))
    expect(inputs.periods.first(3).map { _1.profit_cents_by_business[business.id] }).to eq([ 100_000, 150_000, 150_000 ])
    expect(inputs.periods.first(3).map(&:factor)).to eq([ 4, Rational(12, 5), Rational(3, 2) ])
    expect(inputs.periods.first(3).map(&:elapsed_days)).to eq([ nil, nil, nil ])
  end

  it "projects a period in progress from the days elapsed" do
    deposit(Date.new(2026, 4, 20), 100_000)
    q4 = load(Date.new(2026, 9, 1)).periods.last
    expect(q4).to have_attributes(elapsed_days: 244, factor: Rational(365, 244)) # Sep 1 is day 244 of 2026
    expect(q4.profit_cents_by_business[business.id]).to eq(100_000)
  end

  it "has no data and a factor of 1 for a year that hasn't started" do
    deposit(Date.new(2026, 1, 5), 100_000)
    inputs = load(Date.new(2025, 12, 1))
    expect(inputs.periods.map(&:factor)).to eq([ 1, 1, 1, 1 ])
    expect(inputs.periods.map(&:profit_cents_by_business)).to all(eq({}))
  end

  it "always has all four quarters, even with no businesses" do
    expect(load(Date.new(2026, 4, 1)).periods.map(&:quarter)).to eq([ 1, 2, 3, 4 ])
  end

  it "subtracts mileage and nets collected sales tax" do
    create(:sales_tax_profile, business:)
    taxable = create(:category, :income, business:, sales_tax_treatment: "taxable")
    create(:transaction, account:, category: taxable, posted_on: Date.new(2026, 2, 1), amount_cents: 10_925, sales_tax_cents: 925)
    create(:mileage_entry, business:, driven_on: Date.new(2026, 3, 2), miles_tenths: 100) # 10 miles × 72.5¢ = $7.25
    expect(load(Date.new(2026, 4, 1)).periods.first.profit_cents_by_business[business.id]).to eq(10_000 - 725)
  end

  it "leaves out the personal book and keeps archived businesses" do
    personal = create(:business, :personal, household:)
    deposit(Date.new(2026, 2, 1), 999_999, category: create(:category, :income, business: personal), to: create(:account, business: personal))
    business.update!(archived_at: Time.current)
    inputs = load(Date.new(2026, 4, 1))
    expect(inputs.businesses.map(&:id)).to eq([ business.id ])
    expect(inputs.periods.first.profit_cents_by_business.keys).to eq([ business.id ])
  end

  it "includes every business's owner among the people" do
    other = create(:person, household:)
    create(:business, household:, person: other)
    business
    inputs = load(Date.new(2026, 4, 1))
    expect(inputs.businesses.map(&:person_id) - inputs.people.map(&:id)).to be_empty
    expect(inputs.people.map(&:id)).to include(person.id, other.id)
  end

  it "maps home offices, adjustments, the prior year, and payments" do
    create(:home_office, business:, office_sqft: 200)
    create(:person_adjustment, person:, se_health_insurance_cents: 720_000, retirement_contribution_cents: 600_000, retirement_plan: "sep")
    tax_year = create(:tax_year, household:, prior_year_total_tax_cents: 2_400_000, prior_year_agi_cents: 11_800_000)
    create(:estimated_payment, tax_year:, quarter: 1, amount_cents: 450_000)
    inputs = load(Date.new(2026, 4, 1))
    expect(inputs.businesses.first).to have_attributes(person_id: person.id, home_office_cents: 100_000)
    expect(inputs.people.first).to have_attributes(se_health_insurance_cents: 720_000, retirement_contribution_cents: 600_000, retirement_plan: "sep")
    expect(inputs.prior_year).to eq(Tax::PriorYear.new(total_tax_cents: 2_400_000, agi_cents: 11_800_000))
    expect(inputs.payments).to eq([ Tax::Payment.new(quarter: 1, amount_cents: 450_000) ])
  end

  it "gives people without adjustments zeros" do
    person
    expect(load(Date.new(2026, 4, 1)).people.first).to have_attributes(se_health_insurance_cents: 0, retirement_contribution_cents: 0, retirement_plan: nil)
  end
end
