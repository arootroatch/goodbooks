module Reports
  module CategoryTotals
    COLUMNS = %w[accounts.business_id categories.id categories.name categories.kind categories.schedule_c_line categories.deductible_bps].freeze

    def self.load(business_ids:, range:)
      Transaction.countable.for_businesses(business_ids).where(posted_on: range).joins(:category)
        .group(*COLUMNS).sum("transactions.amount_cents")
        .map do |(business_id, category_id, name, kind, line, bps), sum|
          CategoryTotal.new(business_id:, category_id:, name:, kind:, schedule_c_line: line, deductible_bps: bps, sum_cents: sum)
        end
    end
  end
end
