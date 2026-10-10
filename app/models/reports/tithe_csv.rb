require "csv"

module Reports
  module TitheCsv
    HEADERS = [ "Week starting", "Week ending", "Income", "Owed", "Paid this week", "Applied to this week", "Status", "Balance (positive = behind)" ].freeze

    def self.generate(ledger)
      CSV.generate do |csv|
        csv << HEADERS
        ledger.weeks.each do |week|
          amounts = [ week.income_cents, week.owed_cents, week.paid_cents, week.paid_toward_cents ].map { Money.new(_1).to_input }
          csv << [ week.starts_on.iso8601, week.ends_on.iso8601, *amounts, week.status, Money.new(week.balance_cents).to_input ]
        end
      end
    end
  end
end
