module Reports
  class ScheduleCSummary
    def initialize(category_totals:, mileage_deduction_cents:, home_office_cents: nil)
      @pnl = ProfitAndLoss.new(category_totals:, mileage_deduction_cents:)
      @home_office_cents = home_office_cents
    end

    def lines
      @lines ||= begin
        amounts = Hash.new(0)
        @pnl.income_lines.each { amounts[_1.schedule_c_line] += _1.actual_cents }
        @pnl.expense_lines.each { amounts[_1.schedule_c_line] += _1.deductible_cents }
        amounts["2"] = -amounts["2"] if amounts.key?("2")
        amounts["9"] += @pnl.mileage_deduction_cents if @pnl.mileage_deduction_cents.positive?
        ScheduleC::LINES.keys.select { amounts.key?(_1) }.index_with { amounts[_1] }
      end
    end

    def gross_income_cents = lines.fetch("1", 0) - lines.fetch("2", 0) + lines.fetch("6", 0)
    def total_expenses_cents = lines.except(*ScheduleC::INCOME_LINES).values.sum
    def tentative_profit_cents = gross_income_cents - total_expenses_cents

    # Line 30, capped so the home office never creates a loss.
    def home_office_used_cents
      @home_office_cents && [ @home_office_cents, [ tentative_profit_cents, 0 ].max ].min
    end

    def net_profit_cents = tentative_profit_cents - home_office_used_cents.to_i
  end
end
