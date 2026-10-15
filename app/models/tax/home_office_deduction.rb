module Tax
  module HomeOfficeDeduction
    COST_COLUMNS = %i[rent_cents mortgage_interest_cents utilities_cents insurance_cents repairs_cents other_cents].freeze

    module_function

    def cents(home_office, rate_cents:, max_sqft:)
      if home_office.calculation == "simplified"
        [ home_office.office_sqft, max_sqft ].min * rate_cents
      else
        costs = COST_COLUMNS.sum { home_office.public_send(_1) }
        Money.round_rational(Rational(home_office.office_sqft * costs, home_office.home_sqft)) + home_office.depreciation_cents
      end
    end
  end
end
