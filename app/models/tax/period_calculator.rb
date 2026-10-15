module Tax
  # Parent spec §9.2 steps 1–5 for one Schedule AI period (tax engine spec §4.2).
  class PeriodCalculator
    SE_FLOOR_CENTS = 40_000

    def self.call(...) = new(...).worksheet

    def initialize(params:, businesses:, people:, period:)
      @params = params
      @businesses = businesses
      @people = people
      @period = period
    end

    def worksheet
      business_lines = @businesses.map { business_line(_1) }
      person_lines = @people.map { person_line(_1, business_lines) }
      total_net = business_lines.sum(&:net_profit_cents)
      agi = total_net - person_lines.sum { _1.half_se_cents + _1.health_insurance_cents + _1.retirement_cents }
      before_qbi = [ agi - @params.standard_deduction_cents, 0 ].max
      qbi = [ agi, 0 ].max
      qbi_deduction = rate(@params.qbi_bps, [ qbi, before_qbi ].min)
      taxable = before_qbi - qbi_deduction
      slices = Brackets.slices(taxable, @params.brackets)
      se_total = person_lines.sum(&:se_earnings_cents)

      PeriodWorksheet.new(
        quarter: @period.quarter, factor: @period.factor, elapsed_days: @period.elapsed_days, business_lines:, person_lines:,
        additional_medicare_cents: rate(@params.additional_medicare_bps, [ se_total - @params.additional_medicare_threshold_cents, 0 ].max),
        total_net_profit_cents: total_net, agi_cents: agi, standard_deduction_cents: @params.standard_deduction_cents,
        taxable_before_qbi_cents: before_qbi, qbi_cents: qbi, qbi_deduction_cents: qbi_deduction, taxable_income_cents: taxable,
        bracket_slices: slices, income_tax_cents: slices.sum(&:tax_cents)
      )
    end

    private

    def business_line(business)
      ytd = @period.profit_cents_by_business.fetch(business.id, 0)
      annualized = Money.round_rational(ytd * @period.factor.to_r)
      used = [ business.home_office_cents, [ annualized, 0 ].max ].min
      PeriodWorksheet::BusinessLine.new(business:, ytd_cents: ytd, annualized_cents: annualized, home_office_cents: business.home_office_cents,
                                        home_office_used_cents: used, carryover_cents: business.home_office_cents - used, net_profit_cents: annualized - used)
    end

    def person_line(person, business_lines)
      net = business_lines.select { _1.business.person_id == person.id }.sum(&:net_profit_cents)
      se_earnings = rate(@params.se_earnings_bps, [ net, 0 ].max)
      se_earnings = 0 if se_earnings < SE_FLOOR_CENTS
      ss = rate(@params.ss_rate_bps, [ se_earnings, @params.ss_wage_base_cents ].min)
      medicare = rate(@params.medicare_rate_bps, se_earnings)
      half = Money.round_rational(Rational(ss + medicare, 2))
      retirement = person.retirement_contribution_cents
      health = [ person.se_health_insurance_cents, [ net - half - retirement, 0 ].max ].min
      PeriodWorksheet::PersonLine.new(person:, net_profit_cents: net, se_earnings_cents: se_earnings, ss_cents: ss, medicare_cents: medicare,
                                      half_se_cents: half, retirement_cents: retirement, health_insurance_cents: health)
    end

    def rate(bps, cents) = Money.round_rational(Rational(cents * bps, 10_000))
  end
end
