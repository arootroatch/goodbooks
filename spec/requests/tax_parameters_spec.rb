require "rails_helper"

RSpec.describe "Tax parameters" do
  let!(:business) { create(:business) }

  it "lets the household owner set a year's mileage rate" do
    sign_in_as create(:user, :household_owner)
    post tax_parameters_path, params: { tax_parameter: { year: "2027", mileage_rate_cents: "73" } }
    expect(response).to redirect_to(tax_parameters_path)
    expect(TaxParameters.for_year(2027).standard_mileage_rate_tenth_cents).to eq(730)
  end

  it "rejects a malformed rate" do
    sign_in_as create(:user, :household_owner)
    post tax_parameters_path, params: { tax_parameter: { year: "2027", mileage_rate_cents: "72.55" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "forbids everyone else, even business owners" do
    sign_in_as user_with_role("owner", business)
    get tax_parameters_path
    expect(response).to have_http_status(:forbidden)
  end
end
