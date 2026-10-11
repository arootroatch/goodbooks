require "csv"

module Reports
  module SpendingCsv
    def self.generate(report)
      CSV.generate do |csv|
        csv << [ "Category", *report.months, "Total" ]
        [ *report.income_lines, report.income_total, *report.expense_lines, report.expense_total, report.net ].each do |line|
          csv << [ CsvSafe.text(line.name), *report.months.map { Money.new(line.amounts[_1]).to_input }, Money.new(line.total_cents).to_input ]
        end
      end
    end
  end
end
