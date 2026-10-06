class TransactionsController < ApplicationController
  include BusinessScoped

  IMPORTED_EDITABLE = %i[memo category_id transfer excluded].freeze
  MANUAL_EDITABLE = %i[posted_on payee amount direction memo category_id transfer excluded].freeze

  before_action :require_editor!, except: :index
  before_action :set_transaction, only: %i[edit update destroy]

  def index
    @filter = TransactionFilter.new(Transaction.for_businesses(@business.id).includes(:account, :category), filter_params)
    @transactions = @filter.results
  end

  def new
    @transaction = Transaction.new(posted_on: Date.current, direction: "out")
  end

  def create
    attrs = params.expect(transaction: [:account_id, *MANUAL_EDITABLE])
    account = @business.accounts.manual.find(attrs.delete(:account_id))
    @transaction = account.transactions.new(attrs)
    @transaction.categorized_by = "user" if @transaction.category_id.present?
    if @transaction.save
      redirect_to business_transactions_path(@business), notice: "Transaction added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    permitted = @transaction.account.manual? ? MANUAL_EDITABLE : IMPORTED_EDITABLE
    attrs = params.expect(transaction: permitted)
    @transaction.assign_attributes(attrs)
    @transaction.categorized_by = "user" if attrs.key?(:category_id) || attrs.key?(:transfer)
    if @transaction.save
      redirect_to business_transactions_path(@business), notice: "Transaction updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @transaction.account.manual?
      @transaction.destroy!
      redirect_to business_transactions_path(@business), notice: "Transaction deleted.", status: :see_other
    else
      redirect_to business_transactions_path(@business), alert: "Imported transactions can be excluded, not deleted.", status: :see_other
    end
  end

  private

  def set_transaction
    @transaction = Transaction.for_businesses(@business.id).find(params[:id])
  end

  def filter_params
    params.permit(:from, :to, :account_id, :category_id, :status, :q, :page)
  end
end
