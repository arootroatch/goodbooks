require "rails_helper"

RSpec.describe "Reconnecting a bank" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:owner) { user_with_role("owner", business) }
  let!(:item) { create(:plaid_item, created_by: owner, status: "login_required", last_error: "ITEM_LOGIN_REQUIRED: log in") }
  let!(:account) { create(:account, :plaid, business: business, plaid_item: item, plaid_mask: "0000", name: "Operating") }

  it "opens Link in update mode and marks the item connected afterwards" do
    sign_in_as owner
    get new_plaid_item_reconnection_path(item)
    expect(response.body).to include("link-fake-#{owner.id}-update")
    expect { post plaid_item_reconnection_path(item), params: { public_token: "public-x" } }.to have_enqueued_job(PlaidSyncJob).with(item)
    expect(item.reload).to have_attributes(status: "ok", last_error: nil)
    expect(response).to redirect_to(plaid_item_path(item))
  end

  it "404s for users who can't manage the item" do
    sign_in_as user_with_role("owner", create(:business))
    get new_plaid_item_reconnection_path(item)
    expect(response).to have_http_status(:not_found)
    post plaid_item_reconnection_path(item)
    expect(response).to have_http_status(:not_found)
  end

  it "shows a reconnect banner on the dashboard: a button for managers, text for other members" do
    sign_in_as owner
    get root_path
    expect(response.body).to include("Your connection to Demo Bank needs to be renewed.", new_plaid_item_reconnection_path(item))

    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(response.body).to include("Your connection to Demo Bank needs to be renewed.")
    expect(response.body).not_to include(new_plaid_item_reconnection_path(item))

    sign_in_as user_with_role("owner", create(:business))
    get root_path
    expect(response.body).not_to include("needs to be renewed")

    item.update!(status: "ok")
    sign_in_as owner
    get root_path
    expect(response.body).not_to include("needs to be renewed")
  end

  it "shows Plaid status on the accounts list and a Reconnect link on the item page" do
    sign_in_as user_with_role("viewer", business)
    get business_accounts_path(business)
    expect(response.body).to include("Demo Bank ····0000", "not synced yet", "needs reconnecting")

    sign_in_as owner
    get plaid_item_path(item)
    expect(response.body).to include(new_plaid_item_reconnection_path(item))
  end
end
