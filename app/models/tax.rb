# Federal estimated tax (tax engine spec). Everything is derived on each call; nothing is stored.
module Tax
  def self.estimate(household:, year:, today: Date.current, quarter: nil)
    tax_parameters = TaxParameters.for_year(year)
    return unless tax_parameters&.estimate_ready?

    inputs = Inputs.load(household:, year:, tax_parameters:, today:)
    Estimator.new(inputs).estimate(quarter: quarter || default_quarter(year, today))
  end

  # The tax year whose next installment is due: last year until its January installment's due date passes.
  def self.current_year(today = Date.current) = today <= DueDates.for(today.year - 1).last ? today.year - 1 : today.year

  def self.default_quarter(year, today) = today < Date.new(year) ? 1 : DueDates.quarter_on(year, today)
end
