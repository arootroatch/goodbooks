require "rails_helper"

RSpec.describe "Accounts" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business, name: "Checking") }

  it "lists accounts for viewers" do
    sign_in_as user_with_role("viewer", business)
    get business_accounts_path(business)
    expect(response.body).to include("Checking")
  end

  it "lets owners create a CSV account" do
    sign_in_as user_with_role("owner", business)
    post business_accounts_path(business), params: { account: { name: "Card", source: "csv", kind: "credit" } }
    expect(response).to redirect_to(business_accounts_path(business))
    expect(business.accounts.find_by!(name: "Card")).to be_csv
  end

  it "does not allow creating Plaid accounts by hand" do
    sign_in_as user_with_role("owner", business)
    post business_accounts_path(business), params: { account: { name: "Sneaky", source: "plaid", kind: "checking" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "lets owners archive" do
    sign_in_as user_with_role("owner", business)
    patch business_account_path(business, account), params: { account: { name: "Checking", kind: "checking", archived: "1" } }
    expect(account.reload).to be_archived
  end

  it "forbids editors and viewers from changing accounts" do
    %w[editor viewer].each do |role|
      sign_in_as user_with_role(role, business)
      post business_accounts_path(business), params: { account: { name: "X", source: "manual", kind: "cash" } }
      expect(response).to have_http_status(:forbidden)
      patch business_account_path(business, account), params: { account: { name: "Y" } }
      expect(response).to have_http_status(:forbidden)
      delete session_path
    end
  end

  it "is not found for non-members and for another business's account" do
    other_account = create(:account)
    sign_in_as user_with_role("owner", business)
    get edit_business_account_path(business, other_account)
    expect(response).to have_http_status(:not_found)
    delete session_path
    sign_in_as create(:user)
    get business_accounts_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
