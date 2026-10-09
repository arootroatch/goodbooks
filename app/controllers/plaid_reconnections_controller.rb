class PlaidReconnectionsController < ApplicationController
  include PlaidScoped

  before_action :set_item

  def new
    @link_token = gateway.create_link_token(user: Current.user, access_token: @item.access_token)
  rescue PlaidGateway::Error => e
    redirect_to plaid_item_path(@item), alert: "Plaid: #{e.message}"
  end

  # Link's update mode needs no token exchange: the existing access token works again once the user has logged in.
  def create
    return redirect_to plaid_item_path(@item), notice: "This connection doesn't need reconnecting." unless @item.reconnectable?

    @item.update!(status: "ok", last_error: nil, consent_expires_at: nil)
    PlaidSyncJob.perform_later(@item)
    redirect_to plaid_item_path(@item), notice: "Reconnected #{@item.institution_name}. Syncing now."
  end
end
