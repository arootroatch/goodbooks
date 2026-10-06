module Reports
  class HouseholdProfitAndLoss
    Row = Data.define(:name, :amounts, :total_cents)

    def initialize(by_business)
      @by_business = by_business
    end

    def businesses = @by_business.keys

    def income_rows = rows(:income_lines)
    def expense_rows = rows(:expense_lines)

    def column(metric)
      values = @by_business.to_h { |business, pnl| [ business.id, pnl.public_send(metric) ] }
      values.merge(total: values.values.sum)
    end

    private

    def rows(kind)
      amounts = Hash.new { |h, k| h[k] = {} }
      @by_business.each do |business, pnl|
        pnl.public_send(kind).each { |line| amounts[line.name][business.id] = (amounts[line.name][business.id] || 0) + line.actual_cents }
      end
      amounts.keys.sort.map { |name| Row.new(name:, amounts: amounts[name], total_cents: amounts[name].values.sum) }
    end
  end
end
