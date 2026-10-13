module Tax
  # Everything the estimator reads, as plain values.
  Inputs = Data.define(:year, :params, :businesses, :people, :periods, :prior_year, :payments, :today) do
    const_set(:PERIOD_END_MONTHS, { 1 => 3, 2 => 5, 3 => 8, 4 => 12 }.freeze)

    # Reads the household's business-kind books (archived ones included) for the year, as of today.
    def self.load(household:, year:, tax_parameters:, today: Date.current)
      books = household.businesses.business_kind.order(:name).to_a
      ids = books.map(&:id)
      home_offices = HomeOffice.where(business_id: ids, year:).index_by(&:business_id)
      adjustments = PersonAdjustment.where(person_id: household.people.select(:id), year:).index_by(&:person_id)
      tax_year = household.tax_years.includes(:estimated_payments).find_by(year:)
      profits = Hash.new { |cache, range| cache[range] = profits_for(ids, range) }

      new(
        year:, today:, params: tax_parameters.to_tax_params,
        businesses: books.map do |book|
          BusinessInput.new(id: book.id, name: book.name, person_id: book.person_id,
                            home_office_cents: home_offices[book.id]&.deduction_cents(tax_parameters) || 0)
        end,
        people: household.people.order(:name).map { person_input(_1, adjustments[_1.id]) },
        periods: (1..4).map { period_input(_1, year, today, profits) },
        prior_year: tax_year&.prior_year,
        payments: tax_year ? tax_year.estimated_payments.map { Payment.new(quarter: _1.quarter, amount_cents: _1.amount_cents) } : []
      )
    end

    def self.person_input(person, adjustment)
      PersonInput.new(id: person.id, name: person.name, se_health_insurance_cents: adjustment&.se_health_insurance_cents || 0,
                      retirement_contribution_cents: adjustment&.retirement_contribution_cents || 0, retirement_plan: adjustment&.retirement_plan)
    end

    def self.period_input(quarter, year, today, profits)
      starts_on = Date.new(year)
      ends_on = Date.new(year, self::PERIOD_END_MONTHS.fetch(quarter)).end_of_month
      if ends_on <= today
        PeriodInput.new(quarter:, factor: PeriodInput::FACTORS.fetch(quarter), elapsed_days: nil, profit_cents_by_business: profits[starts_on..ends_on])
      elsif today < starts_on
        PeriodInput.new(quarter:, factor: 1, elapsed_days: 0, profit_cents_by_business: {})
      else
        elapsed = (today - starts_on).to_i + 1
        PeriodInput.new(quarter:, factor: Rational(starts_on.end_of_year.yday, elapsed), elapsed_days: elapsed, profit_cents_by_business: profits[starts_on..today])
      end
    end

    def self.profits_for(ids, range)
      totals = Reports::CategoryTotals.load(business_ids: ids, range:).group_by(&:business_id)
      ids.index_with do |id|
        mileage = Reports::MileageTotals.load(business_ids: [ id ], range:).deduction_cents
        Reports::ScheduleCSummary.new(category_totals: totals.fetch(id, []), mileage_deduction_cents: mileage).tentative_profit_cents
      end
    end

    private_class_method :person_input, :period_input, :profits_for
  end
end
