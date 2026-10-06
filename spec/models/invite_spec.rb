require "rails_helper"

RSpec.describe Invite do
  let(:business) { create(:business) }

  it "stores only a digest of the token and expires in 7 days" do
    invite = create(:invite, business: business)
    expect(invite.token).to be_present
    expect(invite.token_digest).to eq(Invite.digest(invite.token))
    expect(invite.expires_at).to be_within(1.minute).of(7.days.from_now)
    expect(Invite.find_usable(invite.token)).to eq(invite)
  end

  it "is not usable after it expires or is accepted" do
    invite = create(:invite, business: business)
    travel 8.days
    expect(Invite.find_usable(invite.token)).to be_nil
  end

  it "is not usable once accepted" do
    invite = create(:invite, business: business)
    invite.accept!(create(:user))
    expect(Invite.find_usable(invite.token)).to be_nil
  end

  it "rejects grants for archived businesses" do
    business.update!(archived_at: Time.current)
    invite = Invite.new(created_by: create(:user, :household_owner), grant_roles: { business.id => "viewer" })
    expect(invite).not_to be_valid
    expect(invite.errors[:base]).to include("Grant access to active businesses only")
  end

  it "requires at least one grant" do
    invite = Invite.new(created_by: create(:user, :household_owner))
    expect(invite).not_to be_valid
    expect(invite.errors[:base]).to include("Grant access to at least one business")
  end

  it "only lets creators grant businesses they own" do
    editor = user_with_role("editor", business)
    invite = Invite.new(created_by: editor)
    invite.grant_roles = { business.id.to_s => "viewer" }
    expect(invite).not_to be_valid
    owner = user_with_role("owner", business)
    invite = Invite.new(created_by: owner)
    invite.grant_roles = { business.id.to_s => "viewer" }
    expect(invite).to be_valid
  end

  it "ignores blank roles and rejects unknown ones" do
    invite = Invite.new(created_by: create(:user, :household_owner))
    invite.grant_roles = { business.id.to_s => "", create(:business).id.to_s => "admin" }
    expect(invite.grants.size).to eq(1)
    expect(invite).not_to be_valid
  end

  describe "#accept!" do
    let(:invite) { create(:invite, business: business, role: "editor") }
    let(:user) { create(:user) }

    it "grants memberships once" do
      invite.accept!(user)
      expect(user.membership_for(business)).to be_editor
      expect(invite.reload.accepted_by).to eq(user)
      expect { invite.accept!(create(:user)) }.to raise_error(Invite::AlreadyUsed)
    end

    it "refuses when the creator no longer owns the business" do
      creator = user_with_role("owner", business)
      invite = create(:invite, created_by: creator, business: business, role: "owner")
      creator.membership_for(business).update!(role: "viewer")
      expect { invite.accept!(user) }.to raise_error(Invite::AlreadyUsed)
      expect(user.membership_for(business)).to be_nil
    end

    it "upgrades but never downgrades" do
      create(:membership, user: user, business: business, role: "owner")
      invite.accept!(user)
      expect(user.membership_for(business)).to be_owner
    end
  end
end
