class SalesTaxProfile < ApplicationRecord
  include PercentAttribute
  include BusinessKindValidation

  FREQUENCIES = %w[monthly quarterly annual].freeze
  REMITTANCE_CATEGORY_NAME = "Sales tax remittance".freeze

  belongs_to :business

  validates :business_id, uniqueness: true
  validates :filing_frequency, inclusion: { in: FREQUENCIES }
  validates :default_rate_bps, numericality: { only_integer: true, in: 1..2_000, message: "must be between 0.01% and 20%" }
  percent_attribute :default_rate_percent, bps: :default_rate_bps, example: "9.25"
  validates :starts_on, presence: true
  validates :tn_account_number, length: { maximum: 50 }
  validate :starts_on_not_in_future
  validate :calendar_unchanged_once_used, on: :update

  after_save :ensure_remittance_category, if: :active?

  def calendar(today: Date.current)
    SalesTax::Calendar.new(starts_on: starts_on, frequency: filing_frequency, today: today)
  end

  def period_start?(date) = calendar.include_start?(date)

  private

  def starts_on_not_in_future
    errors.add(:starts_on, "can't be in the future") if starts_on && starts_on > Date.current
  end

  def calendar_unchanged_once_used
    return unless will_save_change_to_filing_frequency? || will_save_change_to_starts_on?

    errors.add(:base, "Filings or remittances exist for the current periods.") if calendar_in_use?
  end

  def calendar_in_use?
    business.sales_tax_filings.exists? || Transaction.for_businesses(business_id).where.not(sales_tax_period_starts_on: nil).exists?
  end

  def ensure_remittance_category
    return if business.categories.sales_tax_remittance.exists?

    name = business.categories.exists?(name: REMITTANCE_CATEGORY_NAME) ? "#{REMITTANCE_CATEGORY_NAME} (TN)" : REMITTANCE_CATEGORY_NAME
    business.categories.create!(name: name, kind: "sales_tax_remittance")
  end
end
