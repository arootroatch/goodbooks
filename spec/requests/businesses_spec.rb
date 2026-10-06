require "rails_helper"

RSpec.describe "Businesses" do
  let!(:household) { create(:household) }
  let!(:person) { create(:person, household: household) }
  let(:household_owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, person: person, name: "Pat Consulting"), owner: household_owner) }

  describe "creating" do
    it "lets the household owner create a provisioned business" do
      sign_in_as household_owner
      post businesses_path, params: { business: { name: "Second Gig", person_id: person.id } }
      created = Business.find_by!(name: "Second Gig")
      expect(response).to redirect_to(business_path(created))
      expect(created.accounts.pluck(:name)).to eq(["Cash"])
      expect(household_owner.membership_for(created)).to be_owner
    end

    it "re-renders when invalid" do
      sign_in_as household_owner
      post businesses_path, params: { business: { name: "", person_id: person.id } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "forbids everyone else" do
      sign_in_as user_with_role("owner", business)
      get new_business_path
      expect(response).to have_http_status(:forbidden)
      post businesses_path, params: { business: { name: "Nope", person_id: person.id } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "showing" do
    it "shows a business to a viewer" do
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pat Consulting")
    end

    it "is not found for non-members" do
      sign_in_as create(:user)
      get business_path(business)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "editing" do
    it "lets a business owner rename" do
      owner = user_with_role("owner", business)
      sign_in_as owner
      patch business_path(business), params: { business: { name: "Renamed" } }
      expect(business.reload.name).to eq("Renamed")
    end

    it "forbids editors and viewers" do
      %w[editor viewer].each do |role|
        sign_in_as user_with_role(role, business)
        patch business_path(business), params: { business: { name: "Renamed" } }
        expect(response).to have_http_status(:forbidden)
        delete session_path
      end
    end
  end

  describe "dashboard" do
    it "lists only accessible businesses" do
      other = create(:business, name: "Hidden Biz")
      sign_in_as user_with_role("viewer", business)
      get root_path
      expect(response.body).to include("Pat Consulting")
      expect(response.body).not_to include("Hidden Biz")
      expect(other).to be_persisted
    end
  end
end
