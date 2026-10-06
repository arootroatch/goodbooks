module Reports
  MileageTotal = Data.define(:miles_tenths, :deduction_cents, :missing_rate_years)

  module MileageTotals
    def self.load(business_ids:, range:)
      by_year = MileageEntry.where(business_id: business_ids, driven_on: range).group_by { _1.driven_on.year }
      rates = TaxParameters.where(year: by_year.keys).pluck(:year, :standard_mileage_rate_tenth_cents).to_h

      tenths = 0
      deduction = 0
      missing = []
      by_year.sort.each do |year, entries|
        year_tenths = entries.sum(&:effective_miles_tenths)
        tenths += year_tenths
        if rates[year]
          deduction += MileageDeduction.cents(miles_tenths: year_tenths, rate_tenth_cents: rates[year])
        else
          missing << year
        end
      end
      MileageTotal.new(miles_tenths: tenths, deduction_cents: deduction, missing_rate_years: missing)
    end
  end
end
