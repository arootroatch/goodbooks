module TaxHelpers
  def tax_params_2026 = FactoryBot.build(:tax_parameters, :federal_2026).to_tax_params

  def tax_business(id, person_id: id, home_office_cents: 0) = Tax::BusinessInput.new(id:, name: "Business #{id}", person_id:, home_office_cents:)

  def tax_person(id, health: 0, retirement: 0, plan: nil)
    Tax::PersonInput.new(id:, name: "Person #{id}", se_health_insurance_cents: health, retirement_contribution_cents: retirement, retirement_plan: plan)
  end

  # profits: { business_id => YTD cents }
  def tax_period(quarter, profits, factor: Tax::PeriodInput::FACTORS.fetch(quarter), elapsed_days: nil)
    Tax::PeriodInput.new(quarter:, factor:, elapsed_days:, profit_cents_by_business: profits)
  end

  # ytd: { quarter => { business_id => YTD cents } }
  def tax_periods(ytd) = ytd.map { |quarter, profits| tax_period(quarter, profits) }

  def tax_inputs(ytd:, businesses: [ tax_business(1) ], people: [ tax_person(1) ], prior_year: nil, payments: [], today: Date.new(2027, 2, 1))
    Tax::Inputs.new(year: 2026, params: tax_params_2026, businesses:, people:, periods: tax_periods(ytd), prior_year:, payments:, today:)
  end
end

RSpec.configure { |config| config.include TaxHelpers }
