module SalesTax
  # The only place that turns transactions into sales tax report inputs (spec §5.3).
  module Entries
    Result = Data.define(:deposits, :remittances)

    def self.for(business, range)
      scope = Transaction.countable.for_businesses(business.id).joins(:category)
      deposits = scope.where(posted_on: range, categories: { kind: "income", sales_tax_treatment: %w[taxable exempt] })
        .includes(:account, :category, :invoice_payments).order(:posted_on, :id)
        .map do |txn|
          PeriodReport::Deposit.new(posted_on: txn.posted_on, treatment: txn.category.sales_tax_treatment, gross_cents: txn.gross_cents,
                                    total_tax_cents: txn.total_sales_tax_cents, source: txn)
        end
      remittances = scope.where(categories: { kind: "sales_tax_remittance" }, sales_tax_period_starts_on: range)
        .includes(:account).order(:posted_on, :id)
        .map do |txn|
          PeriodReport::Remittance.new(posted_on: txn.posted_on, amount_cents: txn.amount_cents,
                                       period_starts_on: txn.sales_tax_period_starts_on, source: txn)
        end
      Result.new(deposits: deposits, remittances: remittances)
    end
  end
end
