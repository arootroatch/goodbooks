module Tax
  Estimate = Data.define(:year, :quarter, :worksheets, :ninety_percent_cents, :safe_harbor_cents, :required_annual_cents, :installments, :warnings) do
    def worksheet = worksheets.fetch(quarter)
    def installment = installments.fetch(quarter - 1)
    def next_due_on = installment.due_on
    def pay_at_least_cents = installment.pay_at_least_cents
  end

  class Estimate
    Warning = Data.define(:kind, :message)

    Installment = Data.define(:quarter, :due_on, :regular_cents, :annualized_cents, :paid_cents, :paid_through_cents) do
      def pay_at_least_cents = annualized_cents ? [ regular_cents, annualized_cents ].min : regular_cents
    end
  end
end
