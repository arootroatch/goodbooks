class Invoice < ApplicationRecord
  include MoneyAttribute

  EVENTS = {
    "mark_sent" => { from: %w[draft], to: "sent", verb: "marked sent" },
    "void" => { from: %w[draft sent], to: "void", verb: "voided" },
    "reopen" => { from: %w[void], to: "sent", verb: "reopened" }
  }.freeze
  PDF_MAX_BYTES = 10.megabytes

  money_attribute :amount
  money_attribute :sales_tax, allow_blank: true

  belongs_to :business
  belongs_to :client
  has_many :payments, class_name: "InvoicePayment", dependent: :restrict_with_error
  has_one_attached :pdf

  enum :status, { draft: "draft", sent: "sent", paid: "paid", void: "void" }, validate: true

  validates :number, presence: true, length: { maximum: 50 }, uniqueness: { scope: :business_id }
  validates :issue_date, :due_date, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :description, length: { maximum: 2_000 }
  before_validation { self.sales_tax_cents ||= 0 }

  validate :due_on_or_after_issue
  validate :sales_tax_valid
  validate :client_in_business
  validate :amount_covers_payments
  validate :no_void_with_payments
  validate :pdf_is_a_small_pdf

  def self.receivables_by_business(business_ids, today: Date.current)
    sent.where(business_id: business_ids).includes(:payments).group_by(&:business_id).transform_values do |invoices|
      { outstanding_cents: invoices.sum(&:outstanding_cents),
        overdue_cents: invoices.select { _1.overdue?(today) }.sum(&:outstanding_cents) }
    end
  end

  def paid_cents = payments.loaded? ? payments.sum(&:amount_cents) : payments.sum(:amount_cents)
  def outstanding_cents = amount_cents.to_i - paid_cents
  def partial? = sent? && paid_cents.positive?
  def overdue?(today = Date.current) = sent? && due_date < today
  def days_past_due(today = Date.current) = overdue?(today) ? (today - due_date).to_i : 0
  def can_take_payment? = sent? && outstanding_cents.positive?

  def display_status(today = Date.current)
    if overdue?(today) then "overdue"
    elsif partial? then "partial"
    else status
    end
  end

  def apply_event(event)
    rule = EVENTS.fetch(event)
    unless rule[:from].include?(status)
      errors.add(:base, "This invoice can't be #{rule[:verb]} while it is #{status}.")
      return false
    end
    update(status: rule[:to])
  end

  # The only code that moves an invoice between sent and paid.
  def sync_payment_status!
    return if draft? || void?

    payments.reset
    if outstanding_cents.zero?
      update!(status: "paid", paid_on: payments.joins(:deposit).maximum("transactions.posted_on"))
    else
      update!(status: "sent", paid_on: nil)
    end
  end

  private

  def due_on_or_after_issue
    errors.add(:due_date, "can't be before the issue date") if issue_date && due_date && due_date < issue_date
  end

  def client_in_business
    errors.add(:client, "must belong to this business") if client && client.business_id != business_id
  end

  def sales_tax_valid
    tax = sales_tax_cents.to_i
    if tax.negative? then errors.add(:sales_tax, "can't be negative")
    elsif amount_cents && tax.positive? && tax >= amount_cents then errors.add(:sales_tax, "must be less than the invoice amount")
    elsif tax.positive? && will_save_change_to_sales_tax_cents? && !business&.collects_sales_tax?
      errors.add(:sales_tax, "needs an active sales tax profile")
    end
    return unless persisted? && will_save_change_to_sales_tax_cents? && payments.exists?

    errors.add(:base, "Unlink payments before changing sales tax.")
  end

  def amount_covers_payments
    return unless persisted? && amount_cents

    paid = payments.sum(:amount_cents)
    errors.add(:amount, "can't be less than the #{Money.new(paid)} already paid") if amount_cents < paid
  end

  def no_void_with_payments
    return unless persisted? && will_save_change_to_status?(to: "void") && payments.exists?

    errors.add(:base, "Unlink its payments before voiding this invoice.")
  end

  def pdf_is_a_small_pdf
    return unless pdf.attached?

    errors.add(:pdf, "must be a PDF") unless pdf.blob.content_type == "application/pdf"
    errors.add(:pdf, "must be smaller than 10 MB") if pdf.blob.byte_size > PDF_MAX_BYTES
  end
end
