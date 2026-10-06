class MileageEntry < ApplicationRecord
  belongs_to :business

  validates :driven_on, :purpose, presence: true
  validates :miles_tenths, numericality: { only_integer: true, greater_than: 0, less_than: 2_147_483_647 }, unless: -> { @miles_error }
  validate { errors.add(:miles, @miles_error) if @miles_error }

  def miles
    @miles_input || (miles_tenths && Tenths.format(miles_tenths))
  end

  def miles=(input)
    @miles_input = input
    @miles_error = nil
    self.miles_tenths = Tenths.parse(input)
  rescue Tenths::ParseError => e
    self.miles_tenths = nil
    @miles_error = e.message
  end

  def effective_miles_tenths = round_trip? ? miles_tenths * 2 : miles_tenths
end
