# Unlinks one account from its Plaid connection, so the bank account can be assigned to another book.
class PlaidAccountLinksController < ApplicationController
  include PlaidScoped

  before_action :set_item

  def destroy
    account = @item.accounts.find(params[:account_id])
    account.detach_from_plaid!
    redirect_to plaid_item_path(@item), status: :see_other,
                notice: "Unlinked #{account.name}. Its transactions stay. Assign the bank account again to feed another book."
  end
end
