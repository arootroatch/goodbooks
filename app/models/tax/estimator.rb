module Tax
  # Tax engine spec §4.3–4.4: runs each Schedule AI period up to the selected quarter, then the regular and annualized installments.
  class Estimator
    APPLICABLE_BPS = { 1 => 2_250, 2 => 4_500, 3 => 6_750, 4 => 9_000 }.freeze
    PLAN_NAMES = { "sep" => "SEP", "solo_401k" => "Solo 401(k)" }.freeze
    EMPLOYER_SHARE = Rational(1, 5) # 25% of compensation, which for the self-employed is 20% of profit less half SE tax

    def initialize(inputs)
      @inputs = inputs
      @params = inputs.params
    end

    def estimate(quarter:)
      worksheets = @inputs.periods.select { _1.quarter <= quarter }.sort_by(&:quarter).to_h do |period|
        [ period.quarter, PeriodCalculator.call(params: @params, businesses: @inputs.businesses, people: @inputs.people, period:) ]
      end
      ninety = Money.round_rational(Rational(worksheets.fetch(quarter).total_tax_cents * 9, 10))
      safe_harbor = safe_harbor_cents
      required = safe_harbor ? [ ninety, safe_harbor ].min : ninety

      Estimate.new(year: @inputs.year, quarter:, worksheets:, ninety_percent_cents: ninety, safe_harbor_cents: safe_harbor,
                   required_annual_cents: required, installments: installments(worksheets, required),
                   warnings: warnings(worksheets.fetch(quarter)))
    end

    private

    def safe_harbor_cents
      prior = @inputs.prior_year
      return unless prior

      percent = prior.agi_cents > @params.safe_harbor_high_agi_threshold_cents ? 110 : 100
      Money.round_rational(Rational(prior.total_tax_cents * percent, 100))
    end

    def installments(worksheets, required)
      DueDates.for(@inputs.year).each_with_index.map do |due_on, index|
        quarter = index + 1
        paid_through = @inputs.payments.select { _1.quarter <= quarter }.sum(&:amount_cents)
        annualized = worksheets[quarter] &&
          [ Money.round_rational(Rational(worksheets[quarter].total_tax_cents * APPLICABLE_BPS.fetch(quarter), 10_000)) - paid_through, 0 ].max
        Estimate::Installment.new(
          quarter:, due_on:, annualized_cents: annualized, paid_through_cents: paid_through,
          regular_cents: [ Money.round_rational(Rational(required * quarter, 4)) - paid_through, 0 ].max,
          paid_cents: @inputs.payments.select { _1.quarter == quarter }.sum(&:amount_cents)
        )
      end
    end

    def warnings(worksheet)
      list = []
      list << Estimate::Warning.new(kind: :prior_year_missing, message: "Enter last year's total tax and AGI to use the safe harbor.") unless @inputs.prior_year
      if worksheet.taxable_before_qbi_cents > @params.qbi_threshold_cents
        list << Estimate::Warning.new(kind: :qbi_threshold, message: "Taxable income is above the QBI threshold (#{Money.new(@params.qbi_threshold_cents)}); " \
                                                                     "the simplified QBI deduction may be too high.")
      end
      worksheet.person_lines.each { |line| list << retirement_warning(line) }
      worksheet.business_lines.select { _1.carryover_cents.positive? }.each do |line|
        list << Estimate::Warning.new(kind: :home_office_carryover, message: "#{line.business.name}'s home office (#{Money.new(line.home_office_cents)}) " \
                                                                             "is more than its profit; #{Money.new(line.carryover_cents)} carries over.")
      end
      list.compact
    end

    def retirement_warning(line)
      person = line.person
      return unless person.retirement_contribution_cents.positive? && PLAN_NAMES.key?(person.retirement_plan)

      employer = Money.round_rational([ line.net_profit_cents - line.half_se_cents, 0 ].max * EMPLOYER_SHARE)
      employer += @params.elective_deferral_limit_cents if person.retirement_plan == "solo_401k"
      limit = [ @params.annual_additions_limit_cents, employer ].min
      return if person.retirement_contribution_cents <= limit

      Estimate::Warning.new(kind: :retirement_limit, message: "#{person.name}'s #{PLAN_NAMES.fetch(person.retirement_plan)} contribution " \
                                                              "(#{Money.new(person.retirement_contribution_cents)}) is over the estimated limit (#{Money.new(limit)}).")
    end
  end
end
