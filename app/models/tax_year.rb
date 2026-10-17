class TaxYear < ApplicationRecord
  include Audited
  audited label: -> { "Tax year #{year}" }
  include MoneyAttribute

  belongs_to :household
  has_many :estimated_payments, dependent: :destroy

  money_attribute :prior_year_total_tax, allow_blank: true
  money_attribute :prior_year_agi, allow_blank: true

  validates :year, numericality: { only_integer: true, in: 2000..2100 }, uniqueness: { scope: :household_id }
  validates :prior_year_total_tax_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def self.for(household, year) = household.tax_years.find_or_create_by!(year: year)

  def prior_year
    return unless prior_year_total_tax_cents && prior_year_agi_cents

    Tax::PriorYear.new(total_tax_cents: prior_year_total_tax_cents, agi_cents: prior_year_agi_cents)
  end
end
