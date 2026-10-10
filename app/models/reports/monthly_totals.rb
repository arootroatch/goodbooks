module Reports
  module MonthlyTotals
    Month = Data.define(:month, :income_cents, :expense_cents)
    MONTH_SQL = Arel.sql("CAST(strftime('%m', transactions.posted_on) AS INTEGER)")

    def self.load(business_ids:, year:, through_month:)
      range = Date.new(year, 1, 1)..Date.new(year, through_month, -1)
      sums = Transaction.countable.for_businesses(business_ids).where(posted_on: range).joins(:category)
        .group(MONTH_SQL, "categories.kind").sum("transactions.amount_cents")

      (1..through_month).map do |month|
        Month.new(month:, income_cents: sums.fetch([ month, "income" ], 0), expense_cents: -sums.fetch([ month, "expense" ], 0))
      end
    end
  end
end
