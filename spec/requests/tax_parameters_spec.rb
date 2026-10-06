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

  it "forbids business owners from creating" do
    sign_in_as user_with_role("owner", business)
    expect {
      post tax_parameters_path, params: { tax_parameter: { year: "2027", mileage_rate_cents: "73" } }
    }.not_to change(TaxParameters, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "forbids business owners from updating" do
    tp = create(:tax_parameters, year: 2026, standard_mileage_rate_tenth_cents: 725)
    sign_in_as user_with_role("owner", business)
    patch tax_parameter_path(tp), params: { tax_parameter: { mileage_rate_cents: "70" } }
    expect(response).to have_http_status(:forbidden)
    expect(tp.reload.standard_mileage_rate_tenth_cents).to eq(725)
  end

  it "updates the rate but never the year" do
    tp = create(:tax_parameters, year: 2026, standard_mileage_rate_tenth_cents: 725)
    sign_in_as create(:user, :household_owner)
    patch tax_parameter_path(tp), params: { tax_parameter: { year: "2030", mileage_rate_cents: "70" } }
    tp.reload
    expect(tp.standard_mileage_rate_tenth_cents).to eq(700)
    expect(tp.year).to eq(2026)
  end

  it "rejects an out-of-range rate" do
    sign_in_as create(:user, :household_owner)
    expect {
      post tax_parameters_path, params: { tax_parameter: { year: "2027", mileage_rate_cents: "99999999999999999999" } }
    }.not_to change(TaxParameters, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "falls back to the current year when given an out-of-range year in the new form" do
    sign_in_as create(:user, :household_owner)
    get new_tax_parameter_path(year: "99999")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("value=\"#{Date.current.year}\"")
  end
end
