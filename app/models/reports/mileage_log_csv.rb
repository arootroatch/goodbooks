require "csv"

module Reports
  module MileageLogCsv
    HEADERS = ["Date", "Purpose", "From", "To", "Miles", "Round trip"].freeze

    def self.generate(entries, rate_tenth_cents:, year:)
      total = entries.sum(&:effective_miles_tenths)
      CSV.generate do |csv|
        csv << HEADERS
        entries.each do |e|
          csv << [e.driven_on.iso8601, CsvSafe.text(e.purpose), CsvSafe.text(e.from_location), CsvSafe.text(e.to_location),
                  Tenths.format(e.effective_miles_tenths), e.round_trip? ? "yes" : "no"]
        end
        csv << ["Total", nil, nil, nil, Tenths.format(total), nil]
        if rate_tenth_cents
          deduction = MileageDeduction.cents(miles_tenths: total, rate_tenth_cents: rate_tenth_cents)
          csv << ["Deduction at #{Tenths.format(rate_tenth_cents)}¢/mile", nil, nil, nil, Money.new(deduction).to_input, nil]
        else
          csv << ["Deduction: no IRS rate set for #{year}", nil, nil, nil, nil, nil]
        end
      end
    end
  end
end
