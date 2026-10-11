require "rails_helper"

RSpec.describe BusinessProvisioner do
  let(:owner) { create(:user) }
  let(:business) { build(:business, name: "Pat Consulting") }

  it "creates the business with an owner membership, a Cash account, and template categories" do
    BusinessProvisioner.call(business, owner: owner)

    expect(business).to be_persisted
    expect(owner.membership_for(business).role).to eq("owner")
    expect(business.accounts.map { [ _1.name, _1.source, _1.kind ] }).to eq([ [ "Cash", "manual", "cash" ] ])
    expect(business.categories.count).to eq(CategoryTemplate::CATEGORIES.size)
    expect(business.categories.find_by!(name: "Meals").deductible_bps).to eq(5000)
  end

  it "rolls back everything when the business is invalid" do
    business.name = ""
    expect { BusinessProvisioner.call(business, owner: owner) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Business.count).to eq(0)
    expect(Account.count).to eq(0)
    expect(Membership.count).to eq(0)
    expect(Category.count).to eq(0)
  end

  it "rolls back everything when CategoryTemplate.apply_to raises" do
    expect(Business.count).to eq(0)
    expect(Membership.count).to eq(0)
    expect(Account.count).to eq(0)
    expect(Category.count).to eq(0)

    allow(CategoryTemplate).to receive(:apply_to).and_raise(StandardError, "Category template error")
    expect { BusinessProvisioner.call(business, owner: owner) }.to raise_error(StandardError, "Category template error")

    expect(Business.count).to eq(0)
    expect(Membership.count).to eq(0)
    expect(Account.count).to eq(0)
    expect(Category.count).to eq(0)
  end

  it "adds Merchant fees as the processor-fee category" do
    business = BusinessProvisioner.call(build(:business), owner: create(:user))
    fees = business.categories.find_by!(processor_fees: true)
    expect([ fees.name, fees.kind, fees.schedule_c_line ]).to eq([ "Merchant fees", "expense", "10" ])
    expect(business.categories.find_by!(name: "Sales").sales_tax_treatment).to eq("taxable")
  end
end
