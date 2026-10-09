require "rails_helper"

RSpec.describe "Sales tax page" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let(:owner) { user_with_role("owner", business) }
  let(:params) { { sales_tax_profile: { tn_account_number: "1002003004", filing_frequency: "quarterly", default_rate_percent: "9.25",
                                        starts_on: "2026-01-01", active: "1" } } }

  it "is 404 for non-members and on the personal book" do
    sign_in_as create(:user)
    get business_sales_tax_profile_path(business)
    expect(response).to have_http_status(:not_found)

    household_owner = create(:user, :household_owner)
    book = PersonalBookProvisioner.call(Household.first)
    sign_in_as household_owner
    get business_sales_tax_profile_path(book)
    expect(response).to have_http_status(:not_found)
  end

  it "tells viewers and editors when it isn't set up, and forbids them from setting it up" do
    %w[viewer editor].each do |role|
      sign_in_as user_with_role(role, business)
      get business_sales_tax_profile_path(business)
      expect(response.body).to include("Sales tax isn't set up for this business.")
      patch business_sales_tax_profile_path(business), params: params
      expect(response).to have_http_status(:forbidden)
    end
  end

  it "lets the owner set it up, which creates the remittance category, and lists the periods" do
    sign_in_as owner
    get business_sales_tax_profile_path(business)
    expect(response.body).to include("Default rate (%)")
    patch business_sales_tax_profile_path(business), params: params
    expect(response).to redirect_to(business_sales_tax_profile_path(business))
    expect(business.reload).to be_collects_sales_tax
    expect(business.sales_tax_profile.default_rate_bps).to eq(925)
    expect(business.categories.sales_tax_remittance).to exist
    follow_redirect!
    expect(response.body).to include("Q1 2026", "Apr 20, 2026")
  end

  [ "9.255", "0", "20.01", "abc", "" ].each do |rate|
    it "rejects a rate of #{rate.inspect} without a 500" do
      create(:sales_tax_profile, business: business)
      sign_in_as owner
      patch business_sales_tax_profile_path(business), params: { sales_tax_profile: params[:sales_tax_profile].merge(default_rate_percent: rate) }
      expect(response).to have_http_status(:unprocessable_content)
      expect(business.sales_tax_profile.reload.default_rate_bps).to eq(925)
    end
  end

  it "shows viewers the periods once set up, and hides them while inactive" do
    create(:sales_tax_profile, business: business)
    viewer = user_with_role("viewer", business)
    sign_in_as viewer
    get business_sales_tax_profile_path(business)
    expect(response.body).to include("Q1 2026")
    expect(response.body).not_to include("Default rate (%)")
    business.sales_tax_profile.update!(active: false)
    get business_sales_tax_profile_path(business)
    expect(response.body).to include("Sales tax isn't set up for this business.")
  end

  it "shows Sales tax in the nav to owners always and to others once it is set up" do
    sign_in_as user_with_role("viewer", business)
    get business_path(business)
    expect(response.body).not_to include(">Sales tax<")
    create(:sales_tax_profile, business: business)
    get business_path(business)
    expect(response.body).to include(">Sales tax<")
  end
end
