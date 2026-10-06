require "rails_helper"

RSpec.describe "User business access" do
  let!(:mine) { create(:business) }
  let!(:theirs) { create(:business) }
  let(:user) { user_with_role("viewer", mine) }

  it "lists only businesses with a membership" do
    expect(user.accessible_businesses).to contain_exactly(mine)
  end

  it "finds the membership for a business" do
    expect(user.membership_for(mine).role).to eq("viewer")
    expect(user.membership_for(theirs)).to be_nil
  end

  it "can view the household only with access to every business" do
    expect(user.can_view_household?).to be(false)
    create(:membership, user: user, business: theirs, role: "viewer")
    expect(user.reload.can_view_household?).to be(true)
  end

  it "requires the business person to be in the same household" do
    other_household = Household.create!(name: "Other")
    stranger = Person.create!(household: other_household, name: "Stranger")
    expect(build(:business, household: mine.household, person: stranger)).not_to be_valid
  end

  describe "with no businesses in the household" do
    it "denies view access to a plain user" do
      user = create(:user)
      expect(user.can_view_household?).to be(false)
    end

    it "grants view access to a household owner" do
      user = create(:user, :household_owner)
      expect(user.can_view_household?).to be(true)
    end
  end

  describe "with archived businesses" do
    it "denies view access if archived businesses lack a membership" do
      household = mine.household
      user = user_with_role("viewer", mine)
      archived = create(:business, household: household, archived_at: Time.current)
      expect(user.can_view_household?).to be(false)
    end
  end
end
