class HomeOffice < ApplicationRecord
  include MoneyAttribute
  include BusinessKindValidation

  CALCULATIONS = %w[simplified regular].freeze
  COSTS = %i[rent mortgage_interest utilities insurance repairs other depreciation].freeze

  belongs_to :business

  COSTS.each { money_attribute _1, allow_blank: true }

  before_validation { COSTS.each { |cost| self[:"#{cost}_cents"] ||= 0 } }

  validates :year, numericality: { only_integer: true, in: 2000..2100 }, uniqueness: { scope: :business_id }
  validates :calculation, inclusion: { in: CALCULATIONS }
  validates :office_sqft, numericality: { only_integer: true, greater_than: 0 }
  validate :home_sqft_covers_office
  validate :costs_not_negative

  def regular? = calculation == "regular"

  # Uncapped; nil for the simplified method when the year has no rate.
  def deduction_cents(tax_parameters)
    rate = tax_parameters&.home_office_simplified_rate_cents
    max_sqft = tax_parameters&.home_office_simplified_max_sqft
    return if !regular? && (rate.nil? || max_sqft.nil?)

    Tax::HomeOfficeDeduction.cents(self, rate_cents: rate.to_i, max_sqft: max_sqft.to_i)
  end

  private

  def home_sqft_covers_office
    return unless regular?

    if home_sqft.blank? then errors.add(:home_sqft, "is required for the regular method")
    elsif !home_sqft.to_i.positive? then errors.add(:home_sqft, "must be greater than 0")
    elsif office_sqft && home_sqft < office_sqft then errors.add(:home_sqft, "must be at least the office's square feet")
    end
  end

  def costs_not_negative
    COSTS.each { |cost| errors.add(cost, "can't be negative") if self[:"#{cost}_cents"].to_i.negative? }
  end
end
