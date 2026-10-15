require "rails_helper"

RSpec.describe "Tax parameters" do
  let!(:business) { create(:business) }

  it "lets the household owner set a year's mileage rate" do
    sign_in_as create(:user, :household_owner)
    post tax_parameters_path, params: { tax_parameter: { year: "2027", mileage_rate_cents: "73" } }
    expect(response).to redirect_to(tax_parameters_path)
    expect(TaxParameters.for_year(2027).standard_mileage_rate_tenth_cents).to eq(730)
  end

  it "rejects a malformed rate with a single error message" do
    sign_in_as create(:user, :household_owner)
    post tax_parameters_path, params: { tax_parameter: { year: "2027", mileage_rate_cents: "72.55" } }
    expect(response).to have_http_status(:unprocessable_content)
    tp = TaxParameters.new(year: 2027, mileage_rate_cents: "72.55")
    tp.valid?
    expect(tp.errors.full_messages).to eq([ "Mileage rate cents must be a number with at most one decimal place" ])
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

  describe "federal figures" do
    let(:federal) do
      { mileage_rate_cents: "72.5", standard_deduction_mfj: "32,200", ss_wage_base: "184,500", se_earnings_percent: "92.35",
        ss_rate_percent: "12.4", medicare_rate_percent: "2.9", additional_medicare_percent: "0.9", additional_medicare_threshold_mfj: "250,000",
        qbi_percent: "20", qbi_threshold_mfj: "403,500", home_office_simplified_rate: "5", home_office_simplified_max_sqft: "300",
        safe_harbor_high_agi_threshold: "150,000", annual_additions_limit: "72,000", elective_deferral_limit: "24,500",
        bracket_rows: [ { floor: "0", rate: "10" }, { floor: "24,800", rate: "12%" }, { floor: "", rate: "" } ] }
    end

    it "saves every federal field and drops blank bracket rows" do
      tp = create(:tax_parameters)
      sign_in_as create(:user, :household_owner)
      patch tax_parameter_path(tp), params: { tax_parameter: federal }
      expect(response).to redirect_to(tax_parameters_path)
      tp.reload
      expect(tp.se_earnings_bps).to eq(9235)
      expect(tp.home_office_simplified_max_sqft).to eq(300)
      expect(tp.brackets_mfj.size).to eq(2)
      expect(tp).to be_estimate_ready
    end

    it "still saves a mileage-only edit with the federal fields blank" do
      tp = create(:tax_parameters, year: 2025)
      sign_in_as create(:user, :household_owner)
      patch tax_parameter_path(tp), params: { tax_parameter: { mileage_rate_cents: "70", standard_deduction_mfj: "", se_earnings_percent: "",
                                                               bracket_rows: [ { floor: "", rate: "" } ] } }
      expect(response).to redirect_to(tax_parameters_path)
      expect(tp.reload.standard_mileage_rate_tenth_cents).to eq(700)
    end

    it "re-renders brackets that don't rise, keeping the rows typed" do
      tp = create(:tax_parameters, :federal_2026)
      sign_in_as create(:user, :household_owner)
      patch tax_parameter_path(tp), params: { tax_parameter: { bracket_rows: [ { floor: "100", rate: "10" } ] } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must start at $0 and rise")
      expect(response.body).to include('value="100"')
      expect(tp.reload.brackets_mfj.size).to eq(7)
    end

    it "shows two blank bracket rows after the saved ones" do
      tp = create(:tax_parameters, :federal_2026)
      sign_in_as create(:user, :household_owner)
      get edit_tax_parameter_path(tp)
      expect(response.body.scan('name="tax_parameter[bracket_rows][][floor]"').size).to eq(9)
    end

    it "marks each year complete or incomplete on the list" do
      create(:tax_parameters, :federal_2026)
      create(:tax_parameters, year: 2025)
      sign_in_as create(:user, :household_owner)
      get tax_parameters_path
      expect(response.body).to include("Complete").and include("Mileage only")
    end
  end
end
