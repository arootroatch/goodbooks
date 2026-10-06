class TaxParameters < ApplicationRecord
  self.table_name = "tax_parameters"

  validates :year, presence: true, uniqueness: true, numericality: { only_integer: true, in: 2000..2100 }
  validates :standard_mileage_rate_tenth_cents, numericality: { only_integer: true, greater_than: 0 }
  validate { errors.add(:mileage_rate_cents, @mileage_rate_error) if @mileage_rate_error }

  def self.for_year(year) = find_by(year: year)

  def self.model_name = ActiveModel::Name.new(self, nil, "TaxParameter")

  def mileage_rate_cents
    @mileage_rate_input || (standard_mileage_rate_tenth_cents && Tenths.format(standard_mileage_rate_tenth_cents))
  end

  def mileage_rate_cents=(input)
    @mileage_rate_input = input
    @mileage_rate_error = nil
    self.standard_mileage_rate_tenth_cents = Tenths.parse(input)
  rescue Tenths::ParseError => e
    @mileage_rate_error = e.message
  end
end
