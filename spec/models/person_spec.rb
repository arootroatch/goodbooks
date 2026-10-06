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

  it "enforces two-per-household limit on update" do
    household1 = create(:household)
    household2 = Household.new(name: "Other", singleton: false) # simulates legacy data; the singleton guard forbids a second household
    household2.save!
    create(:person, household: household1)
    create(:person, household: household1)
    person_from_other = create(:person, household: household2)

    expect(person_from_other.update(household: household1)).to be(false)
    expect(person_from_other.errors[:base]).to include("A household has at most two people")
  end
end
