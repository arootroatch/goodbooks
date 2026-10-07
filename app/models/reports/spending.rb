module Reports
  # Month × category grid for the personal book. Expenses display as positive (negated sum), per parent spec §3.
  class Spending
    Row = Data.define(:month, :category_name, :kind, :sum_cents)
    Line = Data.define(:name, :amounts, :total_cents)
    MONTH_SQL = "strftime('%Y-%m', transactions.posted_on)".freeze

    attr_reader :months, :income_lines, :expense_lines, :income_total, :expense_total, :net

    def self.months_in(range)
      first = range.first.beginning_of_month
      (0..).lazy.map { first >> _1 }.take_while { _1 <= range.last }.map { _1.strftime("%Y-%m") }.to_a
    end

    def self.load(business_id:, range:)
      Transaction.countable.for_businesses(business_id).where(posted_on: range).joins(:category)
        .group("categories.name", "categories.kind", Arel.sql(MONTH_SQL)).sum("transactions.amount_cents")
        .map { |(name, kind, month), sum| Row.new(month: month, category_name: name, kind: kind, sum_cents: sum) }
    end

    def initialize(rows, months:)
      @months = months
      @income_lines = lines(rows.select { _1.kind == "income" }, sign: 1)
      @expense_lines = lines(rows.select { _1.kind == "expense" }, sign: -1)
      @income_total = total("Total income", @income_lines)
      @expense_total = total("Total spending", @expense_lines)
      @net = line("Net", months.index_with { @income_total.amounts[_1] - @expense_total.amounts[_1] })
    end

    private

    def lines(rows, sign:)
      rows.group_by(&:category_name).sort.map do |name, list|
        line(name, months.index_with { |month| sign * list.select { _1.month == month }.sum(&:sum_cents) })
      end
    end

    def total(name, lines) = line(name, months.index_with { |month| lines.sum { _1.amounts[month] } })

    def line(name, amounts) = Line.new(name: name, amounts: amounts, total_cents: amounts.values.sum)
  end
end
