require "rails_helper"

RSpec.describe SetupForm do
  let(:attrs) do
    { household_name: "Our House", name: "Pat", email_address: "pat@example.com",
      password: AuthHelpers::PASSWORD, password_confirmation: AuthHelpers::PASSWORD, spouse_name: "Jordan" }
  end

  it "creates the household, the owner user, and both people" do
    user = SetupForm.new(attrs).save
    expect(user).to be_household_owner
    expect(Household.instance.name).to eq("Our House")
    expect(Household.instance.people.pluck(:name)).to contain_exactly("Pat", "Jordan")
    expect(user.person.name).to eq("Pat")
  end

  it "skips the spouse when blank" do
    SetupForm.new(attrs.merge(spouse_name: "")).save
    expect(Person.count).to eq(1)
  end

  it "returns nil with errors and creates nothing when invalid" do
    form = SetupForm.new(attrs.merge(password: "short", password_confirmation: "short"))
    expect(form.save).to be_nil
    expect(form.errors.full_messages.join).to match(/Password/)
    expect(Household.count).to eq(0)
    expect(User.count).to eq(0)
  end

  it "requires a household name" do
    form = SetupForm.new(attrs.merge(household_name: ""))
    expect(form.save).to be_nil
    expect(form.errors[:household_name]).to be_present
  end
end
