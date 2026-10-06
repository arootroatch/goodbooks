require "rails_helper"

RSpec.describe BusinessProvisioner do
  let(:owner) { create(:user) }
  let(:business) { build(:business, name: "Pat Consulting") }

  it "creates the business with an owner membership, a Cash account, and template categories" do
    BusinessProvisioner.call(business, owner: owner)

    expect(business).to be_persisted
    expect(owner.membership_for(business).role).to eq("owner")
    expect(business.accounts.map { [_1.name, _1.source, _1.kind] }).to eq([["Cash", "manual", "cash"]])
    expect(business.categories.count).to eq(CategoryTemplate::CATEGORIES.size)
    expect(business.categories.find_by!(name: "Meals").deductible_bps).to eq(5000)
  end

  it "rolls back everything when the business is invalid" do
    business.name = ""
    expect { BusinessProvisioner.call(business, owner: owner) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Account.count).to eq(0)
    expect(Membership.count).to eq(0)
  end
end
