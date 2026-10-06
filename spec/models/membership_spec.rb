require "rails_helper"

RSpec.describe Membership do
  it "rejects unknown roles" do
    expect(build(:membership, role: "admin")).not_to be_valid
  end

  it "is unique per user and business" do
    existing = create(:membership)
    expect(build(:membership, user: existing.user, business: existing.business)).not_to be_valid
  end

  it "lets owners and editors edit" do
    expect(build(:membership, role: "owner").can_edit?).to be(true)
    expect(build(:membership, role: "editor").can_edit?).to be(true)
    expect(build(:membership, role: "viewer").can_edit?).to be(false)
  end
end
