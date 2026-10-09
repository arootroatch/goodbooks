class InvoicesController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly
  include ScalarParams

  PERMITTED = %i[number issue_date due_date amount sales_tax description pdf].freeze

  before_action :require_editor!, except: %i[index show]
  before_action :set_invoice, only: %i[show edit update destroy mark_sent void reopen]

  def index
    @filter = InvoiceFilter.new(@business.invoices, scalar_params(:status, :client_id, :from, :to, :page))
    respond_to do |format|
      format.html { @invoices = @filter.results }
      format.csv do
        send_data Reports::InvoiceCsv.generate(@filter.all), filename: "#{@business.name.parameterize}-invoices-#{Date.current}.csv", type: "text/csv"
      end
    end
  end

  def show
    @payments = @invoice.payments.includes(deposit: :account).order(:created_at)
  end

  def new
    today = Date.current
    @invoice = @business.invoices.new(number: Invoices::NumberSuggester.next(@business.invoices.pluck(:number)),
                                      issue_date: today, due_date: today + 30, status: "sent")
  end

  def create
    @invoice = @business.invoices.new(params.expect(invoice: PERMITTED))
    @invoice.status = params.dig(:invoice, :status) == "draft" ? "draft" : "sent"
    assign_client
    if save_with_client
      redirect_to business_invoice_path(@business, @invoice), notice: "Invoice added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @invoice.assign_attributes(params.expect(invoice: PERMITTED))
    assign_client
    if save_with_client
      @invoice.sync_payment_status!
      redirect_to business_invoice_path(@business, @invoice), notice: "Invoice updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @invoice.destroy
      redirect_to business_invoices_path(@business), notice: "Invoice deleted.", status: :see_other
    else
      redirect_to business_invoice_path(@business, @invoice), alert: "Unlink its payments before deleting this invoice.", status: :see_other
    end
  end

  def mark_sent = transition("mark_sent", "Invoice marked sent.")
  def void = transition("void", "Invoice voided.")
  def reopen = transition("reopen", "Invoice reopened.")

  private

  def set_invoice
    @invoice = @business.invoices.find(params[:id])
  end

  def transition(event, notice)
    if @invoice.apply_event(event)
      redirect_to business_invoice_path(@business, @invoice), notice: notice, status: :see_other
    else
      redirect_to business_invoice_path(@business, @invoice), alert: @invoice.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # client_id is resolved through the business, never mass-assigned. "new" creates a client from new_client_name.
  def assign_client
    choice = params.dig(:invoice, :client_id)
    return unless choice.is_a?(String) && choice.present?

    if choice == "new"
      @invoice.client = @business.clients.new(name: params.dig(:invoice, :new_client_name).to_s.strip)
    else
      selectable = @business.clients.where(archived_at: nil).or(@business.clients.where(id: @invoice.client_id_was))
      @invoice.client = selectable.find(choice)
    end
  end

  def save_with_client
    ApplicationRecord.transaction do
      client = @invoice.client
      if client&.new_record? && !client.save
        @invoice.validate
        @invoice.errors.add(:client, client.errors.full_messages.to_sentence)
        raise ActiveRecord::Rollback
      end
      @invoice.save || raise(ActiveRecord::Rollback)
    end
  end
end
