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

  it "clamps an absurd date range to 2000-01-01 through today and says so" do
    sign_in_as owner
    get business_spending_report_path(book, from: "0202-01-01", to: "9999-12-31")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("the report covers 2000-01-01 through today")
    expect(response.body).to include("2000-01")
    expect(response.body).not_to include("0202-01")
    expect(response.body).not_to include("9999-12")
    get business_spending_report_path(book, from: "0202-01-01", to: "9999-12-31", format: :csv)
    expect(response.body.lines.first.split(",").size).to be <= 12 * 27 + 3
  end

  it "does not show the notice for an in-range request" do
    sign_in_as owner
    get business_spending_report_path(book, from: "2026-01-01", to: "2026-03-31")
    expect(response.body).not_to include("the report covers")
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
