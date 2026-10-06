require "rails_helper"

# Crafted (non-UI) write requests from users who lack the required role must be refused.
RSpec.describe "Crafted writes" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business) }
  let!(:category) { create(:category, business: business) }
  let!(:owner) { user_with_role("owner", business) }
  let!(:member_membership) { owner.membership_for(business) }

  %w[editor viewer].each do |role|
    it "forbids a #{role} from changing or removing memberships" do
      sign_in_as user_with_role(role, business)
      patch business_membership_path(business, member_membership), params: { membership: { role: "viewer" } }
      expect(response).to have_http_status(:forbidden)
      delete business_membership_path(business, member_membership)
      expect(response).to have_http_status(:forbidden)
      expect(member_membership.reload).to be_owner
    end
  end

  it "forbids a user who owns nothing from creating or revoking invites" do
    invite = create(:invite, created_by: owner, business: business)
    sign_in_as user_with_role("viewer", business)
    expect { post invites_path, params: { invite: { grant_roles: { business.id => "viewer" } } } }.not_to change(Invite, :count)
    expect(response).to have_http_status(:forbidden)
    delete invite_path(invite)
    expect(response).to have_http_status(:forbidden)
    expect(Invite.find_usable(invite.token)).to eq(invite)
  end

  it "forbids a non-household-owner from creating or editing people" do
    person = create(:person, household: household, name: "Jordan")
    sign_in_as owner
    expect { post people_path, params: { person: { name: "Third" } } }.not_to change(Person, :count)
    expect(response).to have_http_status(:forbidden)
    patch person_path(person), params: { person: { name: "Renamed" } }
    expect(response).to have_http_status(:forbidden)
    expect(person.reload.name).to eq("Jordan")
  end

  describe "as a viewer" do
    let!(:viewer) { user_with_role("viewer", business) }
    before { sign_in_as viewer }

    it "forbids updating a CSV mapping" do
      account = create(:account, :csv, business: business)
      upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/checking.csv"), "text/csv")
      import = account.csv_imports.create!(file: upload)
      patch business_account_csv_import_mapping_path(business, account, import),
        params: { csv_import_mapping: { date_column: "Date", payee_column: "Description", amount_column: "Amount", date_format: "MM/DD/YYYY" } }
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids updating a rule" do
      rule = create(:rule, business: business, category: category, value: "adobe")
      patch business_rule_path(business, rule), params: { rule: { value: "changed" } }
      expect(response).to have_http_status(:forbidden)
      expect(rule.reload.value).to eq("adobe")
    end

    it "forbids updating a mileage entry" do
      entry = create(:mileage_entry, business: business, purpose: "Client meeting")
      patch business_mileage_entry_path(business, entry), params: { mileage_entry: { purpose: "changed" } }
      expect(response).to have_http_status(:forbidden)
      expect(entry.reload.purpose).to eq("Client meeting")
    end

    it "forbids updating the business" do
      patch business_path(business), params: { business: { name: "Hijacked" } }
      expect(response).to have_http_status(:forbidden)
      expect(business.reload.name).not_to eq("Hijacked")
    end
  end

  it "returns 404 when moving another business's rule" do
    other = create(:business)
    foreign_rule = create(:rule, business: other)
    sign_in_as user_with_role("editor", business)
    patch move_business_rule_path(business, foreign_rule), params: { position: 1 }, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
