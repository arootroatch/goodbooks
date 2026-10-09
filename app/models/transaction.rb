class Transaction < ApplicationRecord
  include MoneyAttribute

  CATEGORIZED_BY = %w[rule user].freeze
  REVIEW_REASONS = {
    "removed_by_bank" => "Removed by the bank",
    "changed_by_bank" => "The bank changed this transaction; your version was kept"
  }.freeze
  UNALLOCATED_SQL = "transactions.amount_cents - COALESCE((SELECT SUM(invoice_payments.amount_cents) " \
                    "FROM invoice_payments WHERE invoice_payments.deposit_id = transactions.id), 0)".freeze

  money_attribute :amount
  attr_accessor :direction

  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :rule, optional: true
  has_many :invoice_payments, foreign_key: :deposit_id, inverse_of: :deposit, dependent: :restrict_with_error

  scope :inbox, -> { where(category_id: nil, transfer: false, excluded: false) }
  scope :countable, -> { where(transfer: false, excluded: false) }
  scope :needs_review, -> { where.not(review_reason: nil) }
  scope :for_businesses, ->(ids) { joins(:account).where(accounts: { business_id: ids }) }
  scope :linkable_deposits, -> {
    countable.where("transactions.amount_cents > 0")
      .where("transactions.category_id IS NULL OR transactions.category_id IN (SELECT id FROM categories WHERE kind = 'income')")
      .where("#{UNALLOCATED_SQL} > 0")
  }
  scope :with_unallocated, ->(cents) { where("#{UNALLOCATED_SQL} = ?", cents) }

  validates :posted_on, :payee, presence: true
  validates :amount_cents, presence: true, numericality: { only_integer: true }, if: -> { errors[:amount].empty? }
  validates :categorized_by, inclusion: { in: CATEGORIZED_BY }, allow_nil: true
  validates :review_reason, inclusion: { in: REVIEW_REASONS.keys }, allow_nil: true
  validate :category_in_business
  validate :linked_deposit_stays_payable, on: :update
  after_update :resync_linked_invoices, if: :saved_change_to_posted_on?

  before_validation :apply_direction
  before_validation :clear_category_for_transfer

  delegate :business, to: :account

  def inbox? = category_id.nil? && !transfer? && !excluded?

  def categorized_by_user? = categorized_by == "user"

  def imported? = external_id.present? || plaid_transaction_id.present?

  def review_message = REVIEW_REASONS[review_reason]

  def rule_attributes = { payee: payee, memo: memo, amount_cents: amount_cents }

  def allocated_cents = invoice_payments.loaded? ? invoice_payments.sum(&:amount_cents) : invoice_payments.sum(:amount_cents)
  def unallocated_cents = amount_cents - allocated_cents

  def linked_invoice_message
    numbers = invoice_payments.includes(:invoice).map { _1.invoice.number }
    "Linked to #{numbers.join(", ")} — unlink the payment first."
  end

  private

  def apply_direction
    return if direction.blank? || amount_cents.nil?

    self.amount_cents = direction == "out" ? -amount_cents.abs : amount_cents.abs
  end

  def clear_category_for_transfer
    self.category = nil if transfer?
  end

  def linked_deposit_stays_payable
    changed = will_save_change_to_category_id? || will_save_change_to_transfer? ||
              will_save_change_to_excluded? || will_save_change_to_amount_cents?
    return unless changed && invoice_payments.exists?

    payable = !transfer? && !excluded? && category&.income? && amount_cents.to_i >= allocated_cents
    errors.add(:base, linked_invoice_message) unless payable
  end

  def resync_linked_invoices
    invoice_payments.includes(:invoice).each { _1.invoice.sync_payment_status! }
  end

  def category_in_business
    return if category.nil? || account.nil?

    errors.add(:category, "must belong to this business") if category.business_id != account.business_id
  end
end
