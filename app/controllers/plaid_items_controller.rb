class PlaidItemsController < ApplicationController
  include PlaidScoped

  before_action :require_connections_access!, only: :index
  before_action :require_book_owner!, only: %i[new create]
  before_action :set_item, only: %i[show sync destroy]

  def index
    @items = PlaidItem.manageable_by(Current.user).includes(accounts: :business).order(:institution_name)
  end

  def new
    @link_token = gateway.create_link_token(user: Current.user)
  rescue PlaidGateway::Error => e
    redirect_to plaid_items_path, alert: "Plaid: #{e.message}"
  end

  def create
    public_token = params[:public_token].to_s
    return redirect_to(new_plaid_item_path, alert: "Plaid didn't return a connection. Try again.") if public_token.blank?

    exchanged = gateway.exchange_public_token(public_token)
    item = PlaidItem.create!(household: Household.instance, created_by: Current.user, item_id: exchanged[:item_id],
                             access_token: exchanged[:access_token], institution_name: institution_name(exchanged[:access_token]))
    redirect_to plaid_item_path(item), notice: "Connected #{item.institution_name}."
  rescue PlaidGateway::Error => e
    redirect_to new_plaid_item_path, alert: "Plaid: #{e.message}"
  end

  def show
    @plaid_accounts = gateway.accounts(@item.access_token)
  rescue PlaidGateway::Error => e
    @gateway_error = e.message
  end

  def sync
    PlaidSyncJob.perform_later(@item)
    redirect_to plaid_item_path(@item), notice: "Sync started."
  end

  def destroy
    warning = @item.disconnect!(gateway)
    notice = warning ? "Connection removed here. Plaid reported: #{warning}" : "Connection removed."
    redirect_to plaid_items_path, notice: notice, status: :see_other
  end

  private

  # The item exists at Plaid once the token is exchanged, so a failed name lookup must not lose it.
  def institution_name(access_token)
    gateway.institution_name(access_token)
  rescue PlaidGateway::Error
    "Your bank"
  end
end
