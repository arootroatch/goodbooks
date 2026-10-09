class PlaidAssignmentsController < ApplicationController
  include PlaidScoped

  ROW_KEYS = %i[plaid_account choice book target name sync_from].freeze

  before_action :set_item
  helper_method :row_value

  def show
    load_choices(gateway.accounts(@item.access_token))
  rescue PlaidGateway::Error => e
    @gateway_error = e.message
  end

  def update
    plaid_accounts = gateway.accounts(@item.access_token)
    rows = params[:assignments].present? ? params.expect(assignments: [ ROW_KEYS ]) : []
    result = PlaidFeed::Assignment.call(item: @item, user: Current.user, plaid_accounts: plaid_accounts, rows: rows)
    if result.ok?
      PlaidSyncJob.perform_later(@item)
      redirect_to plaid_item_path(@item), notice: "Accounts saved. Syncing now."
    else
      @errors = result.errors
      @submitted = rows.index_by { _1[:plaid_account].to_s }
      load_choices(plaid_accounts)
      render :show, status: :unprocessable_content
    end
  rescue PlaidGateway::Error => e
    redirect_to plaid_item_path(@item), alert: "Plaid: #{e.message}"
  end

  private

  def load_choices(plaid_accounts)
    @plaid_accounts = plaid_accounts
    @assigned = @item.accounts.includes(:business).index_by(&:plaid_account_id)
    @books = Current.user.owned_books.order(:kind, :name)
    @attachable = PlaidFeed::Assignment.attachable(@books).includes(:business).order(:name)
    @errors ||= {}
  end

  def row_value(plaid, key) = (@submitted || {}).fetch(plaid[:account_id], {})[key]
end
