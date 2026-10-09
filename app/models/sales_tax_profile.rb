class SalesTaxProfile < ApplicationRecord
  FREQUENCIES = %w[monthly quarterly annual].freeze
  REMITTANCE_CATEGORY_NAME = "Sales tax remittance".freeze

  belongs_to :business

  validates :business_id, uniqueness: true
  validates :filing_frequency, inclusion: { in: FREQUENCIES }
  validates :default_rate_bps, numericality: { only_integer: true, in: 1..2_000, message: "must be between 0.01% and 20%" }
  validates :starts_on, presence: true
  validates :tn_account_number, length: { maximum: 50 }
  validate :business_kind_only
  validate :starts_on_not_in_future
  validate :default_rate_percent_parses
  validate :calendar_unchanged_once_used, on: :update

  after_save :ensure_remittance_category, if: :active?

  def calendar(today: Date.current)
    SalesTax::Calendar.new(starts_on: starts_on, frequency: filing_frequency, today: today)
  end

  def period_start?(date) = calendar.include_start?(date)

  def default_rate_percent
    return @default_rate_percent_input if defined?(@default_rate_percent_input)
    return if default_rate_bps.nil?

    value = Rational(default_rate_bps, 100)
    value.denominator == 1 ? value.to_i.to_s : format("%.2f", value)
  end

  def default_rate_percent=(input)
    @default_rate_percent_input = input
    stripped = input.to_s.strip.delete_suffix("%").strip
    @default_rate_percent_invalid = !stripped.match?(/\A\d{1,2}(\.\d{1,2})?\z/)
    self.default_rate_bps = @default_rate_percent_invalid ? nil : (Rational(stripped) * 100).round
  end

  private

  def business_kind_only
    errors.add(:business, "must be a business, not the personal book") if business&.personal?
  end

  def starts_on_not_in_future
    errors.add(:starts_on, "can't be in the future") if starts_on && starts_on > Date.current
  end

  def default_rate_percent_parses
    errors.add(:default_rate_percent, "is not a percentage like 9.25") if @default_rate_percent_invalid
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
