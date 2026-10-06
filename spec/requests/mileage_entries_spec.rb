require "rails_helper"

RSpec.describe "Mileage" do
  let!(:business) { create(:business) }

  it "lists the year's entries with the deduction" do
    create(:tax_parameters, year: 2026, standard_mileage_rate_tenth_cents: 725)
    create(:mileage_entry, business: business, miles_tenths: 1234)
    sign_in_as user_with_role("viewer", business)
    get business_mileage_entries_path(business, year: 2026)
    expect(response.body).to include("123.4")
    expect(response.body).to include("$89.47")
  end

  it "asks for the rate when the year has none" do
    create(:mileage_entry, business: business)
    sign_in_as user_with_role("viewer", business)
    get business_mileage_entries_path(business, year: 2026)
    expect(response.body).to include("No IRS mileage rate is set for 2026")
  end

  it "lets editors log a round trip" do
    sign_in_as user_with_role("editor", business)
    post business_mileage_entries_path(business), params: { mileage_entry: {
      driven_on: "2026-03-02", purpose: "Site visit", from_location: "Home", to_location: "Client", miles: "12.5", round_trip: "1"
    } }
    expect(response).to redirect_to(business_mileage_entries_path(business, year: 2026))
    expect(business.mileage_entries.sole.effective_miles_tenths).to eq(250)
  end

  it "re-renders bad miles" do
    sign_in_as user_with_role("editor", business)
    post business_mileage_entries_path(business), params: { mileage_entry: { driven_on: "2026-03-02", purpose: "X", miles: "far" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "forbids viewers from writing" do
    entry = create(:mileage_entry, business: business)
    sign_in_as user_with_role("viewer", business)
    post business_mileage_entries_path(business), params: { mileage_entry: { purpose: "X" } }
    expect(response).to have_http_status(:forbidden)
    delete business_mileage_entry_path(business, entry)
    expect(response).to have_http_status(:forbidden)
  end
end
