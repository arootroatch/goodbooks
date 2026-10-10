class InvoicePayment < ApplicationRecord
  include MoneyAttribute

  money_attribute :amount

  belongs_to :invoice
  belongs_to :deposit, class_name: "Transaction", inverse_of: :invoice_payments

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :deposit_id, uniqueness: { scope: :invoice_id, message: "is already linked to this invoice" }
  validate :deposit_in_invoice_business

  private

  def deposit_in_invoice_business
    return if invoice.nil? || deposit.nil?

    errors.add(:deposit, "must belong to the invoice's business") if deposit.account.business_id != invoice.business_id
  end
end
