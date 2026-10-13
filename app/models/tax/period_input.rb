module Tax
  # elapsed_days is nil once the period has ended; profit_cents_by_business is YTD profit before home office.
  PeriodInput = Data.define(:quarter, :factor, :elapsed_days, :profit_cents_by_business) do
    # Schedule AI annualization factor for each full period (Q1 Jan–Mar through Q4 Jan–Dec).
    const_set(:FACTORS, { 1 => 4, 2 => Rational(12, 5), 3 => Rational(3, 2), 4 => 1 }.freeze)
  end
end
