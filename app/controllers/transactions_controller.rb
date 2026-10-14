class TransactionsController < ApplicationController
  include BusinessScoped
  include ScalarParams

  IMPORTED_EDITABLE = %i[memo category_id transfer excluded goal_id].freeze
  MANUAL_EDITABLE = %i[posted_on payee amount direction memo category_id transfer excluded goal_id].freeze

  SALES_TAX_EDITABLE = %i[processor_fee sales_tax sales_tax_period_starts_on].freeze

  before_action :require_editor!, except: :index
  before_action :set_transaction, only: %i[edit update destroy]

  def index
    @filter = TransactionFilter.new(Transaction.for_businesses(@business.id).includes(:account, :category, :goal), filter_params)
    @transactions = @filter.results
  end

  def new
    @transaction = Transaction.new(posted_on: Date.current, direction: "out")
  end

  def create
    attrs = params.expect(transaction: [ :account_id, *MANUAL_EDITABLE, *SALES_TAX_EDITABLE ])
    account = @business.accounts.manual.find(attrs.delete(:account_id))
    @transaction = account.transactions.new(attrs)
    @transaction.categorized_by = "user" if @transaction.category_id.present?
    @transaction.goal_linked_by = "user" if @transaction.goal_id.present?
    apply_inclusive_tax
    if @transaction.save
      GoalMatcher.new(@business).apply([ @transaction ])
      redirect_after_save("Transaction added.")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    category = @business.categories.find_by(id: params[:category_id]) if params[:category_id].is_a?(String)
    @transaction.category = category if category
  end

  def update
    permitted = (@transaction.imported? ? IMPORTED_EDITABLE : MANUAL_EDITABLE) + SALES_TAX_EDITABLE
    attrs = params.expect(transaction: permitted)
    @transaction.assign_attributes(attrs)
    @transaction.categorized_by = "user" if @transaction.category_id_changed? || @transaction.transfer_changed?
    @transaction.goal_linked_by = "user" if @transaction.goal_id_changed?
    apply_inclusive_tax
    if !@transaction.save
      render :edit, status: :unprocessable_content
    elsif params[:make_rule] == "1" && @transaction.category
      redirect_to new_business_rule_path(@business, value: @transaction.rule_keyword, category_id: @transaction.category_id),
                  notice: "Transaction updated. Now set up the rule."
    else
      redirect_after_save("Transaction updated.")
    end
  end

  def destroy
    if @transaction.imported?
      redirect_to business_transactions_path(@business), alert: "Imported transactions can be excluded, not deleted.", status: :see_other
    elsif @transaction.destroy
      redirect_to business_transactions_path(@business), notice: "Transaction deleted.", status: :see_other
    else
      redirect_to edit_business_transaction_path(@business, @transaction), alert: @transaction.linked_invoice_message, status: :see_other
    end
  end

  private

  def apply_inclusive_tax
    return unless params[:apply_inclusive_tax] == "1" && @business.collects_sales_tax?

    cents = SalesTax::InclusiveTax.call(gross_cents: @transaction.unallocated_cents, rate_bps: @business.sales_tax_profile.default_rate_bps)
    @transaction.sales_tax = Money.new(cents).to_input
    @inclusive_tax_cents = cents
  end

  def redirect_after_save(notice)
    if @inclusive_tax_cents
      rate = @business.sales_tax_profile.default_rate_percent
      redirect_to edit_business_transaction_path(@business, @transaction),
        notice: "Sales tax set to #{Money.new(@inclusive_tax_cents)} (tax-inclusive at #{rate}%)."
    elsif (period_start = period_page_start)
      redirect_to business_sales_tax_period_path(@business, period_start), notice: notice
    else
      redirect_to business_transactions_path(@business), notice: notice
    end
  end

  # The period page's per-remittance select sends the period it came from so the editor lands back there.
  def period_page_start
    Date.iso8601(params[:return_to_period].to_s) if params[:return_to_period].present?
  rescue Date::Error
    nil
  end

  def set_transaction
    @transaction = Transaction.for_businesses(@business.id).find(params[:id])
  end

  def filter_params
    scalar_params(:from, :to, :account_id, :category_id, :status, :q, :page)
  end
end
