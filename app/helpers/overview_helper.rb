module OverviewHelper
  def share_of_income(part_cents, income_cents)
    "#{(100.0 * part_cents / income_cents).round}% of income" if income_cents.positive?
  end
end
