require "rails_helper"

RSpec.describe "User household access with no businesses" do
  before { expect(Business.count).to eq(0) }

  it "denies view access to a plain user" do
    expect(create(:user).can_view_household?).to be(false)
  end

  it "grants view access to a household owner" do
    expect(create(:user, :household_owner).can_view_household?).to be(true)
  end

  it "denies view access to a non-owner linked to a person" do
    user = create(:user, household_owner: false)
    create(:person, user: user, household: create(:household))
    expect(user.household_owner?).to be(false)
    expect(user.can_view_household?).to be(false)
  end

  it "ignores the personal book when deciding household access" do
    business = create(:business)
    PersonalBookProvisioner.call(business.household)
    viewer = user_with_role("viewer", business)
    expect(viewer.can_view_household?).to be(true)
    personal_only = create(:user)
    create(:membership, user: personal_only, business: Business.personal.sole, role: "editor")
    expect(personal_only.can_view_household?).to be(false)
  end
end
