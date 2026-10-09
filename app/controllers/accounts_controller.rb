class AccountsController < ApplicationController
  include BusinessScoped

  CREATABLE_SOURCES = %w[manual csv].freeze

  before_action :require_owner!, except: :index
  before_action :set_account, only: %i[edit update]

  def index
    @accounts = @business.accounts.includes(:plaid_item).order(:archived_at, :name)
    @accounts = @accounts.active unless params[:archived] == "1"
    @show_archived = params[:archived] == "1"
  end

  def new
    @account = @business.accounts.new(source: "manual", kind: "checking")
  end

  def create
    @account = @business.accounts.new(params.expect(account: %i[name source kind]))
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
    attrs = params.expect(account: %i[name kind archived])
    archived = attrs.delete(:archived)
    @account.assign_attributes(attrs)
    @account.archived_at = archived == "1" ? (@account.archived_at || Time.current) : nil unless archived.nil?
    if @account.save
      redirect_to business_accounts_path(@business), notice: "Account updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_account
    @account = @business.accounts.find(params[:id])
  end
end
