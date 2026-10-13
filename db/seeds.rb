# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Reference data for every environment. Safe to run repeatedly.
# Schedule C categories come from CategoryTemplate (code), applied when a business is created.

TaxParameters::Published::YEARS.each do |year, values|
  params = TaxParameters.find_or_create_by!(year: year) do |row|
    row.standard_mileage_rate_tenth_cents = values.fetch(:standard_mileage_rate_tenth_cents)
  end
  blanks = values.select { |column, _| params[column].nil? }
  params.update!(blanks) if blanks.any?
end
