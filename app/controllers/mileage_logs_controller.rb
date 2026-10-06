class MileageLogsController < ApplicationController
  include BusinessScoped

  def show
    year = year_param
    entries = @business.mileage_entries.where(driven_on: Date.new(year).all_year).order(:driven_on)
    rate = TaxParameters.for_year(year)&.standard_mileage_rate_tenth_cents
    send_data Reports::MileageLogCsv.generate(entries, rate_tenth_cents: rate, year: year),
      filename: "#{@business.name.parameterize}-mileage-#{year}.csv", type: "text/csv"
  end
end
