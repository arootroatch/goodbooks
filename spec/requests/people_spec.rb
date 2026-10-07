require "rails_helper"

RSpec.describe "People" do
  let!(:household) { create(:household) }
  let!(:spouse) { create(:person, household: household, name: "Jordan") }
  let(:household_owner) { create(:user, :household_owner) }

  it "lets the household owner link a user to a person" do
    jordan_user = create(:user, name: "Jordan")
    sign_in_as household_owner
    patch person_path(spouse), params: { person: { name: "Jordan", user_id: jordan_user.id } }
    expect(spouse.reload.user).to eq(jordan_user)
  end

  it "refuses a third person" do
    create(:person, household: household)
    sign_in_as household_owner
    post people_path, params: { person: { name: "Third" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "adds a person under a household lock" do
    sign_in_as household_owner
    expect_any_instance_of(Household).to receive(:with_lock).and_call_original
    post people_path, params: { person: { name: "Second" } }
    expect(response).to redirect_to(people_path)
    expect(household.people.count).to eq(2)
  end

  it "rejects a user_id that does not exist" do
    sign_in_as household_owner
    patch person_path(spouse), params: { person: { name: "Jordan", user_id: 0 } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "forbids others" do
    sign_in_as create(:user)
    get people_path
    expect(response).to have_http_status(:forbidden)
  end

  it "gives a newly linked spouse editor access to the personal book" do
    book = PersonalBookProvisioner.call(household)
    spouse_user = create(:user)
    sign_in_as household_owner
    patch person_path(spouse), params: { person: { name: "Jordan", user_id: spouse_user.id } }
    expect(spouse_user.membership_for(book)).to be_editor
  end
end
