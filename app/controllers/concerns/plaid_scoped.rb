# Plaid screens 404 unless Plaid is configured. Items are visible only to their creator and the household owner.
module PlaidScoped
  extend ActiveSupport::Concern

  included do
    before_action :require_plaid!
  end

  private

  def gateway = PlaidGateway.current

  def require_plaid!
    head :not_found unless PlaidGateway.enabled?
  end

  def require_book_owner!
    head :not_found unless Current.user.owned_books.exists?
  end

  def require_connections_access!
    head :not_found unless Current.user.household_owner? || Current.user.owned_books.exists?
  end

  def set_item
    @item = PlaidItem.manageable_by(Current.user).find(params[:plaid_item_id] || params[:id])
  end
end
