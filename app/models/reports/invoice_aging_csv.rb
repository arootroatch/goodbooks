require "csv"

module Reports
  module InvoiceAgingCsv
    HEADERS = [ "Bucket", "Number", "Business", "Client", "Due date", "Days past due", "Outstanding" ].freeze

    def self.generate(report, as_of:)
      CSV.generate do |csv|
        csv << HEADERS
        report.buckets.each do |bucket|
          bucket.rows.each do |row|
            csv << [ bucket.label, CsvSafe.text(row.number), CsvSafe.text(row.business_name), CsvSafe.text(row.client_name),
                     row.due_date.iso8601, InvoiceAging.days_past_due(row.due_date, as_of), Money.new(row.outstanding_cents).to_input ]
          end
        end
      end
    end
  end
end
