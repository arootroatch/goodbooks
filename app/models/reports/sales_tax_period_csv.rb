require "csv"

module Reports
  module SalesTaxPeriodCsv
    HEADERS = [ "Date", "Type", "Account", "Payee", "Gross", "Processor fee", "Sales tax (direct)", "Sales tax (invoices)", "Remitted" ].freeze

    def self.generate(report)
      CSV.generate do |csv|
        csv << HEADERS
        report.deposits.each do |deposit|
          txn = deposit.source
          csv << [ deposit.posted_on.iso8601, deposit.treatment == "taxable" ? "Taxable sale" : "Exempt sale", CsvSafe.text(txn.account.name),
                   CsvSafe.text(txn.payee), cents(deposit.gross_cents), cents(txn.processor_fee_cents), cents(txn.sales_tax_cents),
                   cents(txn.invoice_tax_cents), nil ]
        end
        report.remittances.each do |remittance|
          txn = remittance.source
          csv << [ remittance.posted_on.iso8601, "Remittance", CsvSafe.text(txn.account.name), CsvSafe.text(txn.payee),
                   nil, nil, nil, nil, cents(-remittance.amount_cents) ]
        end
        csv << []
        csv << [ "Gross sales", cents(report.gross_sales_cents) ]
        csv << [ "Exempt sales", cents(report.exempt_sales_cents) ]
        csv << [ "Taxable sales", cents(report.taxable_sales_cents) ]
        csv << [ "Tax collected", cents(report.tax_collected_cents) ]
        csv << [ "Remitted", cents(report.remitted_cents) ]
        csv << [ "Balance owed", cents(report.balance_cents) ]
        csv << [ "Status", report.status ]
      end
    end

    def self.cents(value) = Money.new(value).to_input
    private_class_method :cents
  end
end
