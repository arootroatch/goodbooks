# The only writer of InvoicePayment rows. Locks (and so re-reads) the invoice and the deposit,
# then lets Invoice#sync_payment_status! decide paid vs. sent.
class InvoicePayments
  TAXED_INVOICE_MESSAGE = "This invoice includes sales tax — categorize the deposit as a taxable sale.".freeze

  Result = Data.define(:payment, :error) do
    def ok? = error.nil?
  end

  def self.gross_receipts_categories(business)
    business.categories.gross_receipts.order(:name).to_a
  end

  def self.link(invoice:, deposit:, amount_cents: nil, category: nil, processor_fee_cents: nil)
    ApplicationRecord.transaction do
      invoice.lock!
      deposit.lock!
      error = link_error(invoice, deposit)
      next failure(error) if error

      deposit.processor_fee_cents = processor_fee_cents if processor_fee_cents.to_i.positive? && deposit.processor_fee_cents.zero?
      allocation = Invoices::Allocation.call(
        invoice_amount_cents: invoice.amount_cents, invoice_paid_cents: invoice.paid_cents,
        deposit_gross_cents: deposit.gross_cents, deposit_allocated_cents: deposit.allocated_cents,
        requested_cents: amount_cents
      )
      next failure(allocation.error) unless allocation.ok?

      income = income_category_for(deposit, category, invoice)
      unless income
        next failure(invoice.sales_tax_cents.positive? && category ? TAXED_INVOICE_MESSAGE : "Choose an income category for this deposit.")
      end

      share = Invoices::TaxShare.call(
        invoice_amount_cents: invoice.amount_cents, invoice_tax_cents: invoice.sales_tax_cents, paid_before_cents: invoice.paid_cents,
        shares_before_cents: invoice.payments.sum(:sales_tax_cents), payment_cents: allocation.amount_cents
      )
      if share.positive? && deposit.total_sales_tax_cents + share >= deposit.gross_cents
        next failure("Sales tax on this deposit would reach its gross amount — lower its direct sales tax first.")
      end

      deposit.assign_attributes(category: income, categorized_by: "user") unless deposit.category_id == income.id
      next failure(deposit.errors.full_messages.to_sentence) if deposit.changed? && !deposit.save

      payment = invoice.payments.create!(deposit: deposit, amount_cents: allocation.amount_cents, sales_tax_cents: share)
      invoice.sync_payment_status!
      Result.new(payment: payment, error: nil)
    end
  end

  def self.unlink(payment)
    ApplicationRecord.transaction do
      invoice = payment.invoice
      invoice.lock!
      payment.deposit.lock!
      payment.destroy!
      invoice.sync_payment_status!
      Result.new(payment: payment, error: nil)
    end
  end

  def self.link_error(invoice, deposit)
    if invoice.paid? then "This invoice is already fully paid."
    elsif !invoice.sent? then "Only sent invoices can take payments."
    elsif deposit.account.business_id != invoice.business_id then "That deposit belongs to another business."
    elsif !deposit.amount_cents.positive? then "Only deposits (money in) can pay an invoice."
    elsif deposit.transfer? then "Transfers can't pay an invoice."
    elsif deposit.excluded? then "Excluded transactions can't pay an invoice."
    elsif deposit.category && !deposit.category.income? then "Only deposits in an income category can pay an invoice."
    elsif invoice.sales_tax_cents.positive? && deposit.category && !deposit.category.taxable? then TAXED_INVOICE_MESSAGE
    elsif invoice.payments.exists?(deposit_id: deposit.id) then "That deposit is already linked to this invoice."
    end
  end

  def self.income_category_for(deposit, requested, invoice)
    return deposit.category if deposit.category

    taxed = invoice.sales_tax_cents.positive?
    if requested
      allowed = deposit.business.categories.active.income.exists?(requested.id) && (!taxed || requested.taxable?)
      return allowed ? requested : nil
    end

    candidates = taxed ? deposit.business.categories.taxable_gross_receipts.order(:name).to_a : gross_receipts_categories(deposit.business)
    candidates.first if candidates.one?
  end

  def self.failure(message) = Result.new(payment: nil, error: message)

  private_class_method :link_error, :income_category_for, :failure
end
