module Reports
  class ProfitAndLoss
    Line = Data.define(:name, :schedule_c_line, :actual_cents, :deductible_cents)

    attr_reader :mileage_deduction_cents

    def initialize(category_totals:, mileage_deduction_cents:)
      @totals = category_totals
      @mileage_deduction_cents = mileage_deduction_cents
    end

    def income_lines
      @income_lines ||= @totals.select { _1.kind == "income" }.map do |t|
        Line.new(name: t.name, schedule_c_line: t.schedule_c_line, actual_cents: t.sum_cents, deductible_cents: t.sum_cents)
      end.sort_by(&:name)
    end

    def expense_lines
      @expense_lines ||= @totals.select { _1.kind == "expense" }.map do |t|
        actual = -t.sum_cents
        Line.new(name: t.name, schedule_c_line: t.schedule_c_line, actual_cents: actual,
                 deductible_cents: Money.round_rational(Rational(actual * t.deductible_bps, 10_000)))
      end.sort_by(&:name)
    end

    def total_income_cents = income_lines.sum(&:actual_cents)
    def total_expense_cents = expense_lines.sum(&:actual_cents)
    def total_deductible_expense_cents = expense_lines.sum(&:deductible_cents)
    def net_profit_cents = total_income_cents - total_deductible_expense_cents - mileage_deduction_cents
  end
end
