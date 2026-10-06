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

  it "rejects miles too large to store" do
    sign_in_as user_with_role("editor", business)
    expect {
      post business_mileage_entries_path(business), params: { mileage_entry: { driven_on: "2026-03-02", purpose: "X", miles: "99999999999999999999" } }
    }.not_to change(MileageEntry, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "does not create a row for bad miles" do
    sign_in_as user_with_role("editor", business)
    expect {
      post business_mileage_entries_path(business), params: { mileage_entry: { driven_on: "2026-03-02", purpose: "X", miles: "far" } }
    }.not_to change(MileageEntry, :count)
  end

  context "when editing existing entries" do
    let!(:entry) { create(:mileage_entry, business: business) }
    let(:editor) { user_with_role("editor", business) }

    before { sign_in_as editor }

    it "shows the edit form" do
      get edit_business_mileage_entry_path(business, entry)
      expect(response).to have_http_status(:ok)
    end

    it "updates the entry" do
      patch business_mileage_entry_path(business, entry), params: { mileage_entry: { purpose: "Bank run", miles: "7.5" } }
      expect(response).to redirect_to(business_mileage_entries_path(business, year: 2026))
      entry.reload
      expect(entry.purpose).to eq("Bank run")
      expect(entry.miles_tenths).to eq(75)
    end

    it "deletes the entry" do
      delete business_mileage_entry_path(business, entry)
      expect(MileageEntry.exists?(entry.id)).to be(false)
    end

    it "404s on another business's entry" do
      other = create(:mileage_entry, purpose: "Theirs")
      get edit_business_mileage_entry_path(business, other)
      expect(response).to have_http_status(:not_found)
      patch business_mileage_entry_path(business, other), params: { mileage_entry: { purpose: "Hacked" } }
      expect(response).to have_http_status(:not_found)
      delete business_mileage_entry_path(business, other)
      expect(response).to have_http_status(:not_found)
      expect(other.reload.purpose).to eq("Theirs")
    end
  end

  context "when the year has no rate" do
    it "links a household owner to set it" do
      sign_in_as user_with_role("viewer", business, household_owner: true)
      get business_mileage_entries_path(business, year: 2026)
      expect(response.body).to include(new_tax_parameter_path(year: 2026))
      expect(response.body).not_to include("Deduction at")
    end

    it "tells a non-owner to ask" do
      sign_in_as user_with_role("viewer", business)
      get business_mileage_entries_path(business, year: 2026)
      expect(response.body).to include("Ask the household owner")
      expect(response.body).not_to include(new_tax_parameter_path(year: 2026))
      expect(response.body).not_to include("Deduction at")
    end
  end

  it "falls back to the current year when given an invalid year" do
    sign_in_as user_with_role("viewer", business)
    get business_mileage_entries_path(business, year: "abc")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(Date.current.year.to_s)
  end
end
