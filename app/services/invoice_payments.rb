# app/services/invoice_payments.rb
# The only writer of InvoicePayment rows. Locks (and so re-reads) the invoice and the deposit,
# then lets Invoice#sync_payment_status! decide paid vs. sent.
class InvoicePayments
  Result = Data.define(:payment, :error) do
    def ok? = error.nil?
  end

  def self.gross_receipts_categories(business)
    business.categories.active.income.where(schedule_c_line: "1").order(:name).to_a
  end

  def self.link(invoice:, deposit:, amount_cents: nil, category: nil)
    ApplicationRecord.transaction do
      invoice.lock!
      deposit.lock!
      error = link_error(invoice, deposit)
      next failure(error) if error

      allocation = Invoices::Allocation.call(
        invoice_amount_cents: invoice.amount_cents, invoice_paid_cents: invoice.paid_cents,
        deposit_amount_cents: deposit.amount_cents, deposit_allocated_cents: deposit.allocated_cents,
        requested_cents: amount_cents
      )
      next failure(allocation.error) unless allocation.ok?

      income = income_category_for(deposit, category)
      next failure("Choose an income category for this deposit.") unless income

      deposit.update!(category: income, categorized_by: "user") unless deposit.category_id == income.id
      payment = invoice.payments.create!(deposit: deposit, amount_cents: allocation.amount_cents)
      invoice.sync_payment_status!
      Result.new(payment: payment, error: nil)
    end
  end

  def self.unlink(payment)
    ApplicationRecord.transaction do
      invoice = payment.invoice
      invoice.lock!
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
    elsif invoice.payments.exists?(deposit_id: deposit.id) then "That deposit is already linked to this invoice."
    end
  end

  def self.income_category_for(deposit, requested)
    return deposit.category if deposit.category
    return requested if requested && deposit.business.categories.active.income.exists?(requested.id)
    return nil if requested

    candidates = gross_receipts_categories(deposit.business)
    candidates.first if candidates.one?
  end

  def self.failure(message) = Result.new(payment: nil, error: message)

  private_class_method :link_error, :income_category_for, :failure
end
