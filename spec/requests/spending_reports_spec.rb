require "rails_helper"

RSpec.describe "Spending report" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:book) { PersonalBookProvisioner.call(household) }

  before do
    create(:transaction, account: create(:account, business: book), category: book.categories.find_by!(name: "Groceries"),
                         amount_cents: -4_200, posted_on: Date.current)
  end

  it "shows the grid and exports CSV" do
    sign_in_as owner
    get business_spending_report_path(book)
    expect(response.body).to include("Groceries", "$42.00")
    get business_spending_report_path(book, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Groceries")
  end

  it "is not found for non-members and on business books" do
    business = create(:business)
    sign_in_as user_with_role("owner", business)
    get business_spending_report_path(book)
    expect(response).to have_http_status(:not_found)
    get business_spending_report_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
