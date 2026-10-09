module Reports
  module CategoryTotals
    COLUMNS = %w[accounts.business_id categories.id categories.name categories.kind categories.schedule_c_line categories.deductible_bps].freeze
    # Income is net of collected sales tax and gross of processor fees (sales tax spec §6).
    NET_SQL = "CASE WHEN categories.kind = 'income' THEN transactions.amount_cents + transactions.processor_fee_cents " \
              "- transactions.sales_tax_cents - #{Transaction::INVOICE_TAX_SQL} ELSE transactions.amount_cents END".freeze

    def self.load(business_ids:, range:)
      scope = Transaction.countable.for_businesses(business_ids).where(posted_on: range).joins(:category)
      totals = scope.where(categories: { kind: %w[income expense] }).group(*COLUMNS).sum(Arel.sql(NET_SQL))
        .map do |(business_id, category_id, name, kind, line, bps), sum|
          CategoryTotal.new(business_id:, category_id:, name:, kind:, schedule_c_line: line, deductible_bps: bps, sum_cents: sum)
        end
      fees = scope.where(categories: { kind: "income" }).group("accounts.business_id").sum("transactions.processor_fee_cents")
      with_fees(totals, fees.select { |_, cents| cents.positive? })
    end

    def self.with_fees(totals, fees_by_business)
      return totals if fees_by_business.empty?

      Category.where(business_id: fees_by_business.keys, processor_fees: true).each do |category|
        fee = fees_by_business.fetch(category.business_id)
        index = totals.index { _1.category_id == category.id }
        if index
          totals[index] = totals[index].with(sum_cents: totals[index].sum_cents - fee)
        else
          totals << CategoryTotal.new(business_id: category.business_id, category_id: category.id, name: category.name, kind: category.kind,
                                      schedule_c_line: category.schedule_c_line, deductible_bps: category.deductible_bps, sum_cents: -fee)
        end
      end
      totals
    end
    private_class_method :with_fees
  end
end
