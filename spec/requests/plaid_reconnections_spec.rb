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

  it "clears the renewal-due timestamp on reconnect, and reconnects an item that is only due for renewal" do
    item.update!(status: "ok", consent_expires_at: 3.days.from_now)
    sign_in_as owner
    expect { post plaid_item_reconnection_path(item) }.to have_enqueued_job(PlaidSyncJob).with(item)
    expect(item.reload).to have_attributes(status: "ok", consent_expires_at: nil)
  end

  it "does nothing for an item that doesn't need reconnecting" do
    item.update!(status: "ok", last_error: nil)
    sign_in_as owner
    expect { post plaid_item_reconnection_path(item) }.not_to have_enqueued_job
    expect(response).to redirect_to(plaid_item_path(item))
    expect(flash[:notice]).to eq("This connection doesn't need reconnecting.")
  end

  it "shows an expires-soon banner for an item that is still working but due for renewal" do
    item.update!(status: "ok", consent_expires_at: 3.days.from_now)
    sign_in_as owner
    get root_path
    expect(response.body).to include("Your connection to Demo Bank expires soon. Renew it to keep syncing.", new_plaid_item_reconnection_path(item))
    expect(response.body).not_to include("needs to be renewed")

    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(response.body).to include("expires soon")
    expect(response.body).not_to include(new_plaid_item_reconnection_path(item))
  end

  it "keeps the needs-to-be-renewed wording for a broken item that also has a renewal date" do
    item.update!(status: "login_required", consent_expires_at: 3.days.from_now)
    sign_in_as owner
    get root_path
    expect(response.body).to include("Your connection to Demo Bank needs to be renewed.")
    expect(response.body).not_to include("expires soon")

    item.update!(status: "error", last_error: "boom")
    get root_path
    expect(response.body).to include("needs to be renewed")
    expect(response.body).not_to include("expires soon")
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
