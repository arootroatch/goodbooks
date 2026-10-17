require "rails_helper"

RSpec.describe "Users" do
  let!(:business) { create(:business, name: "Smith Photography") }
  let!(:owner) { user_with_role("owner", business, household_owner: true, name: "Alex") }
  let!(:accountant) { user_with_role("viewer", business, name: "Avery") }

  it "is forbidden to everyone but the household owner" do
    sign_in_as accountant
    get users_path
    expect(response).to have_http_status(:forbidden)
    patch deactivate_user_path(owner)
    expect(response).to have_http_status(:forbidden)
  end

  it "lists users with their books and roles" do
    sign_in_as owner
    get users_path
    expect(response.body).to include("Avery", "Smith Photography", "Viewer", "Household owner")
  end

  it "signs a user out everywhere" do
    accountant.sessions.create!
    sign_in_as owner
    patch sign_out_user_path(accountant)
    expect(accountant.sessions.count).to eq(0)
    expect(response).to redirect_to(users_path)
  end

  it "removes and reactivates a user" do
    sign_in_as owner
    patch deactivate_user_path(accountant)
    expect(flash[:notice]).to eq("Avery removed from the household.")
    expect(accountant.reload).to be_deactivated
    get users_path
    expect(response.body).to include("Removed")
    patch reactivate_user_path(accountant)
    expect(accountant.reload).not_to be_deactivated
    expect(AuditEvent.where(action: "summary").pluck(:summary)).to eq([ "Removed Avery from the household", "Reactivated Avery" ])
  end

  it "explains a refusal" do
    sign_in_as owner
    patch deactivate_user_path(owner)
    expect(flash[:alert]).to eq("You can't remove yourself.")
  end
end
