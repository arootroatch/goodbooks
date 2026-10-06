require "csv"

module Reports
  module TransactionCsv
    HEADERS = [ "Date", "Business", "Account", "Payee", "Memo", "Amount", "Category", "Schedule C line", "Transfer", "Deductible amount" ].freeze

    def self.generate(transactions)
      CSV.generate do |csv|
        csv << HEADERS
        transactions.each do |txn|
          category = txn.category
          deductible =
            if category&.expense? then Money.round_rational(Rational(-txn.amount_cents * category.deductible_bps, 10_000))
            elsif category&.income? then txn.amount_cents
            end
          csv << [
            txn.posted_on.iso8601, CsvSafe.text(txn.account.business.name), CsvSafe.text(txn.account.name),
            CsvSafe.text(txn.payee), CsvSafe.text(txn.memo), Money.new(txn.amount_cents).to_input,
            CsvSafe.text(category&.name), category&.schedule_c_line, txn.transfer? ? "yes" : "no",
            deductible && Money.new(deductible).to_input
          ]
        end
      end
    end
  end
end
