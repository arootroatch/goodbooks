require "rails_helper"

RSpec.describe "Plaid account assignment" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:owner) { user_with_role("owner", business) }
  let!(:item) { create(:plaid_item, created_by: owner) }
  let!(:csv) { create(:account, :csv, business: business, name: "Business Checking") }

  before { sign_in_as owner }

  it "lists the bank's accounts with the choices" do
    get plaid_item_assignment_path(item)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Plaid Checking", "····0000", "Plaid Credit Card", "Pat Consulting", "Business Checking")
  end

  it "applies the assignment and starts a sync" do
    params = { assignments: [
      { plaid_account: "fake-checking", choice: "attach", book: business.id, target: csv.id, name: "", sync_from: "" },
      { plaid_account: "fake-card", choice: "new", book: business.id, target: "", name: "Business Card", sync_from: "" },
      { plaid_account: "fake-savings", choice: "skip", book: business.id, target: "", name: "", sync_from: "" }
    ] }
    expect { patch plaid_item_assignment_path(item), params: params }.to have_enqueued_job(PlaidSyncJob).with(item)
    expect(response).to redirect_to(plaid_item_path(item))
    expect(csv.reload.plaid_account_id).to eq("fake-checking")
    expect(business.accounts.find_by!(name: "Business Card")).to be_plaid
  end

  it "re-renders with the row's error and keeps what was entered" do
    params = { assignments: [ { plaid_account: "fake-card", choice: "new", book: create(:business).id, target: "", name: "Typed name", sync_from: "" } ] }
    patch plaid_item_assignment_path(item), params: params
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Choose a book you own", "Typed name")
    expect(Account.where(plaid_account_id: "fake-card")).to be_empty
  end

  it "shows assigned accounts read-only" do
    create(:account, :plaid, business: business, plaid_item: item, plaid_account_id: "fake-checking", name: "Operating")
    get plaid_item_assignment_path(item)
    expect(response.body).to include("Assigned to Pat Consulting › Operating")
  end

  it "404s for users who can't manage the item" do
    sign_in_as user_with_role("owner", create(:business))
    get plaid_item_assignment_path(item)
    expect(response).to have_http_status(:not_found)
  end
end
