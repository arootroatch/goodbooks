module Reports
  module BucketTotals
    Row = Data.define(:label, :income_cents, :expense_cents)

    def self.load(business_ids:, buckets:)
      return [] if buckets.empty?

      sums = Transaction.countable.for_businesses(business_ids)
        .where(posted_on: buckets.first.range.first..buckets.last.range.last).joins(:category)
        .group(:posted_on, "categories.kind").sum("transactions.amount_cents")

      buckets.map do |bucket|
        in_bucket = sums.select { |(day, _), _| bucket.range.cover?(day) }
        Row.new(label: bucket.label,
                income_cents: in_bucket.sum { |(_, kind), cents| kind == "income" ? cents : 0 },
                expense_cents: -in_bucket.sum { |(_, kind), cents| kind == "expense" ? cents : 0 })
      end
    end
  end
end
