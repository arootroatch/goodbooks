require "rails_helper"

RSpec.describe Person do
  it "allows at most two people per household" do
    household = create(:household)
    create(:person, household: household)
    create(:person, household: household)
    third = build(:person, household: household)
    expect(third).not_to be_valid
    expect(third.errors[:base]).to include("A household has at most two people")
  end

  it "links to at most one user" do
    user = create(:user)
    create(:person, user: user)
    expect(build(:person, user: user)).not_to be_valid
  end
end
