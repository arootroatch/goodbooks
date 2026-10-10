module OverviewHelper
  def period_options(range, today: Date.current)
    {
      "Month" => today.beginning_of_month..today,
      "Quarter" => today.beginning_of_quarter..today,
      "YTD" => today.beginning_of_year..today
    }.map { |label, period| [ label, { from: period.first.iso8601, to: period.last.iso8601 }, period == range ] }
  end

  def share_of_income(part_cents, income_cents)
    "#{(100.0 * part_cents / income_cents).round}% of income" if income_cents.positive?
  end

  def month_in_progress?(date, today: Date.current) = date.year == today.year && date.month == today.month
end
