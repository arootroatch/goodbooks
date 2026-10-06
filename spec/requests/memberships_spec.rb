require "rails_helper"

RSpec.describe "Memberships" do
  let!(:business) { create(:business) }
  let!(:owner) { user_with_role("owner", business) }

  it "lets owners change roles" do
    member = user_with_role("viewer", business)
    sign_in_as owner
    patch business_membership_path(business, member.membership_for(business)), params: { membership: { role: "editor" } }
    expect(response).to redirect_to(business_memberships_path(business))
    expect(member.membership_for(business)).to be_editor
  end

  it "rejects invalid or missing roles gracefully" do
    member = user_with_role("viewer", business)
    sign_in_as owner
    path = business_membership_path(business, member.membership_for(business))
    patch path, params: { membership: { role: "admin" } }
    expect(response).to redirect_to(business_memberships_path(business))
    expect(flash[:alert]).to eq("Choose a valid role.")
    patch path, params: { membership: { role: "" } }
    expect(flash[:alert]).to eq("Choose a valid role.")
    patch path
    expect(flash[:alert]).to eq("Choose a valid role.")
    expect(member.membership_for(business)).to be_viewer
  end

  it "returns 404 to members of other businesses" do
    membership = owner.membership_for(business)
    sign_in_as user_with_role("owner", create(:business))
    get business_memberships_path(business)
    expect(response).to have_http_status(:not_found)
    patch business_membership_path(business, membership), params: { membership: { role: "viewer" } }
    expect(response).to have_http_status(:not_found)
    delete business_membership_path(business, membership)
    expect(response).to have_http_status(:not_found)
  end

  it "refuses to demote or remove the last owner" do
    sign_in_as owner
    membership = owner.membership_for(business)
    patch business_membership_path(business, membership), params: { membership: { role: "viewer" } }
    expect(membership.reload).to be_owner
    delete business_membership_path(business, membership)
    expect(Membership.exists?(membership.id)).to be(true)
    expect(flash[:alert]).to eq("A business needs at least one owner.")
  end

  describe "household owner's membership" do
    let!(:household_owner) { create(:user, :household_owner).tap { |u| create(:membership, user: u, business: business, role: "owner") } }
    let(:membership) { household_owner.membership_for(business) }
    let(:message) { "The household owner's access can only be changed by the household owner." }

    it "cannot be demoted by another business owner" do
      sign_in_as owner
      patch business_membership_path(business, membership), params: { membership: { role: "viewer" } }
      expect(response).to redirect_to(business_memberships_path(business))
      expect(flash[:alert]).to eq(message)
      expect(membership.reload).to be_owner
    end

    it "cannot be removed by another business owner" do
      sign_in_as owner
      delete business_membership_path(business, membership)
      expect(flash[:alert]).to eq(message)
      expect(Membership.exists?(membership.id)).to be(true)
    end

    it "can be changed by the household owner themselves" do
      sign_in_as household_owner
      patch business_membership_path(business, membership), params: { membership: { role: "editor" } }
      expect(membership.reload).to be_editor
    end
  end

  it "removes members" do
    member = user_with_role("viewer", business)
    sign_in_as owner
    delete business_membership_path(business, member.membership_for(business))
    expect(member.membership_for(business)).to be_nil
  end

  it "forbids non-owners" do
    sign_in_as user_with_role("editor", business)
    get business_memberships_path(business)
    expect(response).to have_http_status(:forbidden)
  end
end
