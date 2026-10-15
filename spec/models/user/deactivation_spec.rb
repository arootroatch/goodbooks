require "rails_helper"

RSpec.describe User::Deactivation do
  let!(:business) { create(:business, name: "Smith Photography") }
  let!(:owner) { user_with_role("owner", business, household_owner: true, name: "Alex") }
  let!(:accountant) { user_with_role("viewer", business, name: "Avery") }

  def deactivate(user, by: owner) = Audit.as(by) { described_class.call(user, by:) }

  it "removes memberships, ends sessions, revokes their invites and deactivates" do
    accountant.sessions.create!
    accountant.memberships.find_by(business:).update!(role: "owner")
    other_owner = user_with_role("owner", business)
    invite = Invite.create!(created_by: accountant, grant_roles: { business.id => "viewer" })
    result = deactivate(accountant)
    expect(result).to be_ok
    expect(accountant.reload).to be_deactivated
    expect(accountant.memberships).to be_empty
    expect(accountant.sessions).to be_empty
    expect(Invite.find_usable(invite.token)).to be_nil
    expect(other_owner.membership_for(business)).to be_owner
    expect(AuditEvent.where(action: "summary").pluck(:summary)).to eq([ "Removed Avery from the household" ])
    expect(AuditEvent.where(auditable_type: "Membership", action: "destroy").count).to eq(1)
  end

  it "refuses yourself, household owners, and the last owner of a book" do
    expect(deactivate(owner).error).to eq("You can't remove yourself.")
    expect(deactivate(create(:user, :household_owner), by: owner).error).to eq("Household owners can't be removed.")
    accountant.memberships.find_by(business:).update!(role: "owner")
    owner.memberships.find_by(business:).update!(role: "editor")
    expect(deactivate(accountant).error).to eq("Avery is the last owner of Smith Photography. Make someone else an owner first.")
    expect(accountant.reload).not_to be_deactivated
    expect(accountant.memberships).not_to be_empty
  end
end
