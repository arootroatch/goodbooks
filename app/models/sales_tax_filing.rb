class SalesTaxFiling < ApplicationRecord
  belongs_to :business

  validates :period_starts_on, :filed_on, presence: true
  validates :period_starts_on, uniqueness: { scope: :business_id, message: "is already filed" }
  validates :confirmation_number, length: { maximum: 100 }
  validate :filed_on_not_in_future
  validate :period_in_calendar

  private

  def filed_on_not_in_future
    errors.add(:filed_on, "can't be in the future") if filed_on && filed_on > Date.current
  end

  def period_in_calendar
    return if period_starts_on.nil? || business.nil?

    errors.add(:period_starts_on, "isn't a filing period for this business") unless business.sales_tax_profile&.period_start?(period_starts_on)
  end
end
