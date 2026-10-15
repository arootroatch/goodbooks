require "rails_helper"

RSpec.describe "Tax adjustments" do
  let!(:household) { create(:household) }
  let!(:owner_person) { create(:person, household:, name: "Alex") }
  let!(:spouse_user) { create(:user) }
  let!(:spouse) { create(:person, household:, name: "Whitney", user: spouse_user) }
  let!(:business) { create(:business, household:, person: owner_person) }
  let!(:spouse_business) { create(:business, household:, person: spouse) }
  let(:params) { { person_adjustment: { se_health_insurance: "7,200", retirement_contribution: "6,000", retirement_plan: "sep" } } }

  before do
    create(:membership, user: spouse_user, business: spouse_business, role: "editor")
    create(:membership, user: spouse_user, business:, role: "viewer")
  end

  it "lets the household owner edit anyone's" do
    sign_in_as create(:user, :household_owner)
    patch person_adjustment_path(spouse, 2026), params: params
    expect(response).to redirect_to(tax_year_path(2026))
    expect(spouse.person_adjustments.find_by!(year: 2026)).to have_attributes(se_health_insurance_cents: 720_000, retirement_plan: "sep")
  end

  it "lets a person's own user edit theirs" do
    sign_in_as spouse_user
    get edit_person_adjustment_path(spouse, 2026)
    expect(response).to have_http_status(:ok)
    patch person_adjustment_path(spouse, 2026), params: params
    expect(response).to redirect_to(tax_year_path(2026))
  end

  it "keeps a person's own user without household access on their form after saving" do
    spouse_user.memberships.find_by!(business:).destroy!
    sign_in_as spouse_user
    patch person_adjustment_path(spouse, 2026), params: params
    expect(response).to redirect_to(edit_person_adjustment_path(spouse, 2026))
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Adjustments saved.")
  end

  it "forbids editing someone else's when the user can see the household" do
    sign_in_as spouse_user
    get edit_person_adjustment_path(owner_person, 2026)
    expect(response).to have_http_status(:forbidden)
  end

  it "404s someone else's when the user can't see the household" do
    sign_in_as user_with_role("owner", create(:business, household:, person: owner_person))
    get edit_person_adjustment_path(spouse, 2026)
    expect(response).to have_http_status(:not_found)
  end

  it "requires a plan with a contribution" do
    sign_in_as spouse_user
    patch person_adjustment_path(spouse, 2026), params: { person_adjustment: { retirement_contribution: "6,000", retirement_plan: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Retirement plan is required with a contribution")
  end

  it "404s a bad year" do
    sign_in_as spouse_user
    get "/people/#{spouse.id}/adjustments/20x6/edit"
    expect(response).to have_http_status(:not_found)
  end
end
