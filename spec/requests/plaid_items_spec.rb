require "rails_helper"

RSpec.describe "Plaid items" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business) }
  let!(:owner) { user_with_role("owner", business) }

  it "404s every Plaid screen when Plaid is disabled" do
    item = create(:plaid_item, created_by: owner)
    sign_in_as owner
    PlaidGateway.current = nil
    [ plaid_items_path, new_plaid_item_path, plaid_item_path(item) ].each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
    end
    get root_path
    expect(response.body).not_to include(plaid_items_path)
  end

  it "lets a book owner open Link and shows Banks in the nav" do
    sign_in_as owner
    get root_path
    expect(response.body).to include(plaid_items_path)
    get new_plaid_item_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="plaid-link"', "link-fake-#{owner.id}", 'data-plaid-link-fake-value="true"')
  end

  it "404s connecting for a user who owns no book" do
    editor = user_with_role("editor", business)
    sign_in_as editor
    get new_plaid_item_path
    expect(response).to have_http_status(:not_found)
    post plaid_items_path, params: { public_token: "public-x" }
    expect(response).to have_http_status(:not_found)
    get plaid_items_path
    expect(response).to have_http_status(:not_found)
  end

  it "exchanges the public token and creates the item" do
    sign_in_as owner
    expect { post plaid_items_path, params: { public_token: "public-x" } }.to change(PlaidItem, :count).by(1)
    item = PlaidItem.last
    expect(item).to have_attributes(household: household, created_by: owner, institution_name: "Demo Bank", status: "ok")
    expect(item.access_token).to start_with("access-fake-")
    expect(response).to redirect_to(plaid_item_assignment_path(item))
  end

  it "reports a missing token or a Plaid failure without creating anything" do
    sign_in_as owner
    post plaid_items_path, params: { public_token: "" }
    expect(response).to redirect_to(new_plaid_item_path)
    plaid_gateway.fail_next(:exchange_public_token, PlaidGateway::Error.new("INVALID_PUBLIC_TOKEN: expired"))
    post plaid_items_path, params: { public_token: "public-x" }
    expect(flash[:alert]).to eq("Plaid: INVALID_PUBLIC_TOKEN: expired")
    expect(PlaidItem.count).to eq(0)
  end

  describe "an existing item" do
    let!(:item) { create(:plaid_item, created_by: owner, access_token: "access-1") }
    let!(:account) do
      create(:account, :plaid, business: business, plaid_item: item, plaid_account_id: "fake-checking", plaid_name: "Plaid Checking",
                               plaid_mask: "0000", name: "Operating")
    end

    it "is visible to its creator and the household owner, and 404 for other book owners" do
      sign_in_as owner
      get plaid_item_path(item)
      expect(response.body).to include("Demo Bank", "Operating", "····0000")
      get plaid_items_path
      expect(response.body).to include(plaid_item_path(item))

      sign_in_as create(:user, :household_owner)
      get plaid_item_path(item)
      expect(response).to have_http_status(:ok)

      sign_in_as user_with_role("owner", create(:business))
      get plaid_item_path(item)
      expect(response).to have_http_status(:not_found)
    end

    it "marks an account Plaid no longer reports" do
      account.update!(plaid_account_id: "gone")
      sign_in_as owner
      get plaid_item_path(item)
      expect(response.body).to include("No longer reported by the bank")
    end

    it "never renders the access token" do
      sign_in_as owner
      get plaid_item_path(item)
      expect(response.body).not_to include("access-1")
    end

    it "starts a sync" do
      sign_in_as owner
      expect { post sync_plaid_item_path(item) }.to have_enqueued_job(PlaidSyncJob).with(item)
      expect(response).to redirect_to(plaid_item_path(item))
    end

    it "removes the connection, keeping the account and its transactions" do
      account.update!(csv_mapping: { "date_column" => "Date" })
      manual_account = create(:account, :plaid, business: business, plaid_item: item, plaid_account_id: "fake-card")
      txn = create(:transaction, account: account, plaid_transaction_id: "t1")
      sign_in_as owner
      delete plaid_item_path(item)
      expect(response).to redirect_to(plaid_items_path)
      expect(flash[:notice]).to eq("Connection removed.")
      expect(PlaidItem.exists?(item.id)).to be(false)
      expect(account.reload).to have_attributes(source: "csv", plaid_item_id: nil, plaid_account_id: nil, plaid_sync_from: nil)
      expect(manual_account.reload.source).to eq("manual")
      expect(txn.reload.plaid_transaction_id).to eq("t1")
      expect(plaid_gateway.calls).to include(:item_remove)
    end

    it "removes the connection locally even when Plaid fails" do
      plaid_gateway.fail_next(:item_remove, PlaidGateway::Error.new("ITEM_NOT_FOUND: gone"))
      sign_in_as owner
      delete plaid_item_path(item)
      expect(flash[:notice]).to eq("Connection removed here. Plaid reported: ITEM_NOT_FOUND: gone")
      expect(PlaidItem.exists?(item.id)).to be(false)
    end
  end
end
