class EstimatedPayment < ApplicationRecord
  include MoneyAttribute

  belongs_to :tax_year
  belongs_to :debit, class_name: "Transaction", optional: true, inverse_of: :estimated_payment

  money_attribute :amount

  before_validation :default_quarter

  validates :quarter, inclusion: { in: 1..4 }
  validates :paid_on, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :debit_id, uniqueness: { message: "is already recorded as a payment" }, allow_nil: true
  validate :debit_is_money_out

  def link(debit)
    self.debit = debit
    self.amount_cents = -debit.amount_cents
    self.paid_on = debit.posted_on
  end

  private

  def default_quarter
    self.quarter = nil if quarter.blank?
    self.quarter ||= Tax::DueDates.quarter_on(tax_year.year, paid_on) if tax_year && paid_on
  end

  def debit_is_money_out
    errors.add(:debit, "must be money paid out") if debit && debit.amount_cents >= 0
  end
end
