class InvoicePaymentsController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly
  include DateRangeParams
  include ScalarParams

  RECENT_DAYS = 90
  LIMIT = 100

  before_action :require_editor!
  before_action :set_invoice

  def new
    unless @invoice.can_take_payment?
      return redirect_to business_invoice_path(@business, @invoice), alert: "Only sent invoices with a balance can take payments."
    end

    @from = parse_date(params[:from]) || Date.current - RECENT_DAYS
    deposits = Transaction.for_businesses(@business.id).linkable_deposits.includes(:account, :category, :invoice_payments)
      .where.not(id: @invoice.payments.select(:deposit_id))
    @exact = deposits.with_unallocated(@invoice.outstanding_cents).order(posted_on: :desc, id: :desc).limit(LIMIT).to_a
    @others = deposits.where(posted_on: @from..).where.not(id: @exact.map(&:id)).order(posted_on: :desc, id: :desc).limit(LIMIT).to_a
    @gross_receipts = InvoicePayments.gross_receipts_categories(@business)
    @income_categories = @business.categories.active.income.order(:name)
  end

  def create
    deposit = Transaction.for_businesses(@business.id).find(scalar_params(:deposit_id)[:deposit_id])
    result = link(deposit)
    return respond_for_inbox(result, deposit) if params[:from_inbox] == "1"

    if result.ok?
      redirect_to business_invoice_path(@business, @invoice), notice: "Payment recorded.", status: :see_other
    elsif @invoice.reload.can_take_payment?
      redirect_to new_business_invoice_payment_path(@business, @invoice), alert: result.error, status: :see_other
    else
      redirect_to business_invoice_path(@business, @invoice), alert: result.error, status: :see_other
    end
  end

  def destroy
    InvoicePayments.unlink(@invoice.payments.find(params[:id]))
    redirect_to business_invoice_path(@business, @invoice), notice: "Payment unlinked.", status: :see_other
  end

  private

  def set_invoice
    @invoice = @business.invoices.find(params[:invoice_id])
  end

  def link(deposit)
    cents, error = requested_cents
    return InvoicePayments::Result.new(payment: nil, error: error) if error

    category_id = scalar_params(:category_id)[:category_id]
    category = category_id && @business.categories.active.income.find(category_id)
    InvoicePayments.link(invoice: @invoice, deposit: deposit, amount_cents: cents, category: category)
  end

  def respond_for_inbox(result, deposit)
    respond_to do |format|
      format.turbo_stream do
        if result.ok?
          render turbo_stream: turbo_stream.remove(deposit)
        else
          render turbo_stream: turbo_stream.replace(deposit, partial: "inboxes/row", locals: {
            business: @business, txn: deposit.reload, categories: @business.categories.active.order(:name), editable: true,
            matcher: InvoiceMatcher.for_businesses([ @business.id ]), error: result.error
          })
        end
      end
      format.html do
        flash_message = result.ok? ? { notice: "Payment recorded." } : { alert: result.error }
        redirect_back_or_to business_inbox_path(@business), **flash_message
      end
    end
  end

  def requested_cents
    return [ nil, nil ] unless params.key?(:amount)

    text = scalar_params(:amount)[:amount]
    return [ nil, "Amount can't be blank." ] if text.nil?

    [ Money.parse(text).cents, nil ]
  rescue Money::ParseError => e
    [ nil, "Amount #{e.message}." ]
  end
end
