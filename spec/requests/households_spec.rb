require "rails_helper"

RSpec.describe "Household settings" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }

  it "lets the household owner change the name and IRS payment URL" do
    sign_in_as create(:user, :household_owner)
    get edit_household_path
    expect(response.body).to include("https://www.irs.gov/payments/direct-pay")
    patch household_path, params: { household: { name: "The Roots", irs_payment_url: "https://www.irs.gov/payments" } }
    expect(response).to redirect_to(edit_household_path)
    expect(household.reload).to have_attributes(name: "The Roots", irs_payment_url: "https://www.irs.gov/payments")
  end

  it "rejects a URL that isn't https" do
    sign_in_as create(:user, :household_owner)
    patch household_path, params: { household: { irs_payment_url: "javascript:alert(1)" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(household.reload.irs_payment_url).to eq(Household::DEFAULT_IRS_PAYMENT_URL)
  end

  it "forbids everyone else" do
    sign_in_as user_with_role("owner", business)
    get edit_household_path
    expect(response).to have_http_status(:forbidden)
    patch household_path, params: { household: { name: "Nope" } }
    expect(response).to have_http_status(:forbidden)
  end
end
