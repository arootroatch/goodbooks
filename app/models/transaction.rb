class Transaction < ApplicationRecord
  include MoneyAttribute

  CATEGORIZED_BY = %w[rule user].freeze
  UNALLOCATED_SQL = "transactions.amount_cents + transactions.processor_fee_cents - COALESCE((SELECT SUM(invoice_payments.amount_cents) " \
                    "FROM invoice_payments WHERE invoice_payments.deposit_id = transactions.id), 0)".freeze
  INVOICE_TAX_SQL = "COALESCE((SELECT SUM(invoice_payments.sales_tax_cents) FROM invoice_payments " \
                    "WHERE invoice_payments.deposit_id = transactions.id), 0)".freeze
  TAXED_SQL = "transactions.sales_tax_cents > 0 OR #{INVOICE_TAX_SQL} > 0".freeze

  money_attribute :amount
  money_attribute :sales_tax, allow_blank: true
  money_attribute :processor_fee, allow_blank: true
  attr_accessor :direction

  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :rule, optional: true
  has_many :invoice_payments, foreign_key: :deposit_id, inverse_of: :deposit, dependent: :restrict_with_error

  scope :inbox, -> { where(category_id: nil, transfer: false, excluded: false) }
  scope :countable, -> { where(transfer: false, excluded: false) }
  scope :for_businesses, ->(ids) { joins(:account).where(accounts: { business_id: ids }) }
  scope :linkable_deposits, -> {
    countable.where("transactions.amount_cents > 0")
      .where("transactions.category_id IS NULL OR transactions.category_id IN (SELECT id FROM categories WHERE kind = 'income')")
      .where("#{UNALLOCATED_SQL} > 0")
  }
  scope :with_unallocated, ->(cents) { where("#{UNALLOCATED_SQL} = ?", cents) }
  scope :needing_sales_tax, -> {
    countable.joins(:category).where(categories: { kind: "income", sales_tax_treatment: "taxable" })
      .where(sales_tax_cents: 0).where.not(id: InvoicePayment.select(:deposit_id))
  }

  validates :posted_on, :payee, presence: true
  validates :amount_cents, presence: true, numericality: { only_integer: true }, if: -> { errors[:amount].empty? }
  validates :categorized_by, inclusion: { in: CATEGORIZED_BY }, allow_nil: true
  validate :category_in_business
  validate :linked_deposit_stays_payable, on: :update
  validate :processor_fee_allowed
  validate :sales_tax_allowed
  validate :remittance_period_in_calendar
  after_update :resync_linked_invoices, if: :saved_change_to_posted_on?

  before_validation :apply_direction
  before_validation :clear_category_for_transfer
  before_validation :default_sales_amounts
  before_validation :assign_remittance_period

  delegate :business, to: :account

  def inbox? = category_id.nil? && !transfer? && !excluded?

  def categorized_by_user? = categorized_by == "user"

  def rule_attributes = { payee: payee, memo: memo, amount_cents: amount_cents }

  def allocated_cents = invoice_payments.loaded? ? invoice_payments.sum(&:amount_cents) : invoice_payments.sum(:amount_cents)
  def unallocated_cents = gross_cents - allocated_cents

  def gross_cents = amount_cents.to_i + processor_fee_cents.to_i

  def invoice_tax_cents
    invoice_payments.loaded? ? invoice_payments.sum(&:sales_tax_cents) : invoice_payments.sum(:sales_tax_cents)
  end

  def total_sales_tax_cents = sales_tax_cents.to_i + (new_record? ? 0 : invoice_tax_cents)
  def net_income_cents = gross_cents - total_sales_tax_cents

  def linked_invoice_message
    numbers = invoice_payments.includes(:invoice).map { _1.invoice.number }
    "Linked to #{numbers.join(", ")} — unlink the payment first."
  end

  private

  def assign_remittance_period
    if category&.sales_tax_remittance?
      self.sales_tax_period_starts_on ||= SalesTax::RemittancePeriod.default_for(account.business, posted_on) if account
    else
      self.sales_tax_period_starts_on = nil
    end
  end

  def remittance_period_in_calendar
    return if sales_tax_period_starts_on.nil?

    profile = account&.business&.sales_tax_profile
    errors.add(:sales_tax_period_starts_on, "isn't a filing period for this business") unless profile&.period_start?(sales_tax_period_starts_on)
  end

  def apply_direction
    return if direction.blank? || amount_cents.nil?

    self.amount_cents = direction == "out" ? -amount_cents.abs : amount_cents.abs
  end

  def clear_category_for_transfer
    self.category = nil if transfer?
  end

  def default_sales_amounts
    self.sales_tax_cents ||= 0
    self.processor_fee_cents ||= 0
  end

  def processor_fee_allowed
    fee = processor_fee_cents.to_i
    return errors.add(:processor_fee, "can't be negative") if fee.negative?
    return if fee.zero?

    if account&.business&.personal? then errors.add(:processor_fee, "isn't used on the personal book")
    elsif amount_cents.to_i <= 0 then errors.add(:processor_fee, "only applies to money in")
    elsif transfer? || excluded? || (category && !category.income?) then errors.add(:base, "Clear the processor fee first.")
    end
  end

  def sales_tax_allowed
    direct = sales_tax_cents.to_i
    return errors.add(:sales_tax, "can't be negative") if direct.negative?

    total = total_sales_tax_cents
    return if total.zero?

    if direct.positive? && will_save_change_to_sales_tax_cents? && !account&.business&.collects_sales_tax?
      errors.add(:sales_tax, "needs an active sales tax profile")
    elsif amount_cents.to_i <= 0 then errors.add(:sales_tax, "only applies to money in")
    elsif transfer? || excluded? || !category&.taxable? then errors.add(:base, "Clear the sales tax first.")
    elsif total >= gross_cents then errors.add(:sales_tax, "must be less than the gross amount #{Money.new(gross_cents)}")
    end
  end

  def linked_deposit_stays_payable
    changed = will_save_change_to_category_id? || will_save_change_to_transfer? ||
              will_save_change_to_excluded? || will_save_change_to_amount_cents? ||
              will_save_change_to_processor_fee_cents?
    return unless changed && invoice_payments.exists?

    payable = !transfer? && !excluded? && category&.income? && gross_cents >= allocated_cents
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
