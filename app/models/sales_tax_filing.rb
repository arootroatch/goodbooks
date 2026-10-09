class SalesTaxFiling < ApplicationRecord
  belongs_to :business

  validates :period_starts_on, :filed_on, presence: true
  validates :period_starts_on, uniqueness: { scope: :business_id, message: "is already filed" }
  validates :confirmation_number, length: { maximum: 100 }
  validate :filed_on_not_in_future
  validate :period_in_calendar
  validate :period_has_ended

  private

  def filed_on_not_in_future
    errors.add(:filed_on, "can't be in the future") if filed_on && filed_on > Date.current
  end

  def period_has_ended
    return if period_starts_on.nil? || filed_on.nil? || business&.sales_tax_profile.nil?

    period = business.sales_tax_profile.calendar(today: [ filed_on, Date.current ].max).period_for(period_starts_on)
    errors.add(:filed_on, "can't be filed before the period ends") if period && filed_on <= period.ends_on
  end

  def period_in_calendar
    return if period_starts_on.nil? || business.nil?

    errors.add(:period_starts_on, "isn't a filing period for this business") unless business.sales_tax_profile&.period_start?(period_starts_on)
  end
end
