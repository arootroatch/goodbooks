class AccountsController < ApplicationController
  include BusinessScoped
  include Archiving

  CREATABLE_SOURCES = %w[manual csv].freeze
  BALANCE_FIELDS = %i[opening_balance opening_balance_on].freeze

  before_action :require_owner!, except: :index
  before_action :set_account, only: %i[edit update archive unarchive]

  def index
    @accounts = @business.accounts.includes(:plaid_item).order(:archived_at, :name)
    @accounts = @accounts.active unless params[:archived] == "1"
    @show_archived = params[:archived] == "1"
  end

  def new
    @account = @business.accounts.new(source: "manual", kind: "checking")
  end

  def create
    @account = @business.accounts.new(params.expect(account: %i[name source kind tithable] + BALANCE_FIELDS))
    unless CREATABLE_SOURCES.include?(@account.source)
      @account.errors.add(:source, "must be manual or CSV")
      return render :new, status: :unprocessable_content
    end

    if @account.save
      redirect_to business_accounts_path(@business), notice: "Account created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    fields = @account.plaid? ? %i[name kind tithable] : %i[name kind tithable] + BALANCE_FIELDS
    if @account.update(params.expect(account: fields))
      redirect_to business_accounts_path(@business), notice: "Account updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def archivable = @account

  def set_account
    @account = @business.accounts.find(params[:id])
  end
end
