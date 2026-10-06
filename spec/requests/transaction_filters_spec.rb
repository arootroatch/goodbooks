require "rails_helper"

RSpec.describe "Transaction list filters" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business) }
  let!(:mine) { create(:transaction, account: account, payee: "My own payee") }
  let!(:other_account) { create(:account) }
  let!(:theirs) { create(:transaction, account: other_account, payee: "Other business payee") }

  before { sign_in_as user_with_role("viewer", business) }

  it "never shows another business's transactions when filtering by its account" do
    get business_transactions_path(business, account_id: other_account.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Other business payee")
    expect(response.body).not_to include("My own payee")
  end

  it "ignores non-scalar filter values" do
    get business_transactions_path(business, account_id: [ account.id ], q: { "x" => "y" })
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("My own payee")
  end

  it "still filters by its own account" do
    get business_transactions_path(business, account_id: account.id)
    expect(response.body).to include("My own payee")
  end
end
