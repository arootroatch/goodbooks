module Tax
  # One Schedule AI period, every line of it. Amounts are annualized.
  PeriodWorksheet = Data.define(
    :quarter, :factor, :elapsed_days, :business_lines, :person_lines, :additional_medicare_cents, :total_net_profit_cents, :agi_cents,
    :standard_deduction_cents, :taxable_before_qbi_cents, :qbi_cents, :qbi_deduction_cents, :taxable_income_cents, :bracket_slices, :income_tax_cents
  ) do
    def se_tax_cents = person_lines.sum(&:se_tax_cents)
    def total_tax_cents = income_tax_cents + se_tax_cents + additional_medicare_cents
  end

  class PeriodWorksheet
    BusinessLine = Data.define(:business, :ytd_cents, :annualized_cents, :home_office_cents, :home_office_used_cents, :carryover_cents, :net_profit_cents)
    PersonLine = Data.define(:person, :net_profit_cents, :se_earnings_cents, :ss_cents, :medicare_cents, :half_se_cents, :retirement_cents, :health_insurance_cents) do
      def se_tax_cents = ss_cents + medicare_cents
    end
  end
end
