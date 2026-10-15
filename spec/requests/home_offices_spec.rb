require "rails_helper"

RSpec.describe "Home office" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }
  let!(:household_owner) { create(:user, :household_owner).tap { create(:membership, user: _1, business:, role: "owner") } }
  let(:simplified) { { home_office: { calculation: "simplified", office_sqft: "200" } } }

  before do
    create(:tax_parameters, :federal_2026)
    income = create(:category, :income, business:)
    create(:transaction, account: create(:account, business:), category: income, posted_on: Date.new(2026, 2, 1), amount_cents: 50_000)
  end

  it "lets the household owner add one, capped on Schedule C line 30" do
    sign_in_as household_owner
    get edit_business_home_office_path(business, 2026)
    expect(response).to have_http_status(:ok)
    patch business_home_office_path(business, 2026), params: simplified
    expect(response).to redirect_to(business_schedule_c_path(business, year: 2026))
    follow_redirect!
    # 200 sq ft × $5 = $1,000.00, capped at the $500.00 tentative profit
    line30 = Nokogiri::HTML(response.body).css("tr").find { _1.text.include?("Line 30") }
    expect(line30.text).to include("$500.00").and include("Edit home office")
    expect(response.body).to include("Tentative profit")
  end

  it "lets a business owner who isn't the household owner edit their own" do
    sign_in_as user_with_role("owner", business)
    patch business_home_office_path(business, 2026), params: simplified
    expect(HomeOffice.find_by!(business:, year: 2026).office_sqft).to eq(200)
  end

  it "forbids an editor" do
    sign_in_as user_with_role("editor", business)
    get edit_business_home_office_path(business, 2026)
    expect(response).to have_http_status(:forbidden)
    patch business_home_office_path(business, 2026), params: simplified
    expect(response).to have_http_status(:forbidden)
  end

  it "404s a non-member, the personal book, and a bad year" do
    sign_in_as user_with_role("owner", create(:business, household:))
    get edit_business_home_office_path(business, 2026)
    expect(response).to have_http_status(:not_found)

    personal = create(:business, :personal, household:)
    create(:membership, user: household_owner, business: personal, role: "owner")
    delete session_path
    sign_in_as household_owner
    get edit_business_home_office_path(personal, 2026)
    expect(response).to have_http_status(:not_found)
    get "/businesses/#{business.id}/home_offices/abc/edit"
    expect(response).to have_http_status(:not_found)
  end

  it "re-renders a regular office bigger than the home" do
    sign_in_as household_owner
    patch business_home_office_path(business, 2026), params: { home_office: { calculation: "regular", office_sqft: "300", home_sqft: "200" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be at least the office&#39;s square feet")
  end

  it "shows a dash and an add link on Schedule C when there's none, and no link for a viewer" do
    sign_in_as household_owner
    get business_schedule_c_path(business, year: 2026)
    expect(response.body).to include("Add home office")
    delete session_path
    sign_in_as user_with_role("viewer", business)
    get business_schedule_c_path(business, year: 2026)
    expect(response.body).not_to include("Add home office")
  end

  it "links the home office from the taxes page for those who can edit it" do
    travel_to Date.new(2026, 5, 1) do
      sign_in_as household_owner
      get tax_year_path(2026)
      expect(response.body).to include(edit_business_home_office_path(business, 2026))
    end
  end
end
