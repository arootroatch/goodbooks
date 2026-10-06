require "csv"

module Reports
  module InvoiceCsv
    HEADERS = [ "Number", "Business", "Client", "Issue date", "Due date", "Amount", "Paid", "Outstanding", "Status", "Paid on", "Description" ].freeze

    def self.generate(invoices, today: Date.current)
      CSV.generate do |csv|
        csv << HEADERS
        invoices.each do |invoice|
          csv << [
            CsvSafe.text(invoice.number), CsvSafe.text(invoice.business.name), CsvSafe.text(invoice.client.name),
            invoice.issue_date.iso8601, invoice.due_date.iso8601, Money.new(invoice.amount_cents).to_input,
            Money.new(invoice.paid_cents).to_input, Money.new(invoice.outstanding_cents).to_input,
            invoice.display_status(today), invoice.paid_on&.iso8601, CsvSafe.text(invoice.description)
          ]
        end
      end
    end
  end
end
