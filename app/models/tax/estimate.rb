module Tax
  Estimate = Data.define(:year, :quarter, :worksheets, :ninety_percent_cents, :safe_harbor_cents, :required_annual_cents, :installments, :warnings) do
    def worksheet = worksheets.fetch(quarter)
    def installment = installments.fetch(quarter - 1)
    def next_due_on = installment.due_on
    def pay_at_least_cents = installment.pay_at_least_cents
    def paid_cents = installments.sum(&:paid_cents)

    # Share of the year's required payments made so far, rounded down; 100 when nothing is required.
    def paid_percent
      return 100 unless required_annual_cents.positive?

      [ paid_cents * 100 / required_annual_cents, 100 ].min
    end
  end

  class Estimate
    Warning = Data.define(:kind, :message)

    Installment = Data.define(:quarter, :due_on, :regular_cents, :annualized_cents, :paid_cents, :paid_through_cents) do
      def pay_at_least_cents = annualized_cents ? [ regular_cents, annualized_cents ].min : regular_cents
      def past_due?(today) = due_on < today && pay_at_least_cents.positive?
    end
  end
end
