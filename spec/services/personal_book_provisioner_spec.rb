require "rails_helper"

RSpec.describe PersonalBookProvisioner do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }

  it "creates the book once, with personal categories and no Cash account" do
    book = described_class.call(household)
    expect(book).to be_personal
    expect(book.name).to eq("Personal")
    expect(book.accounts).to be_empty
    expect(book.categories.find_by!(name: "Tithe")).to be_tithe
    expect(described_class.call(household)).to eq(book)
    expect(Business.personal.count).to eq(1)
  end

  it "makes the household owner an owner and linked people editors, never the accountant" do
    spouse = create(:user)
    create(:person, household: household, user: spouse)
    accountant = create(:user)
    book = described_class.call(household)
    expect(owner.membership_for(book)).to be_owner
    expect(spouse.membership_for(book)).to be_editor
    expect(accountant.membership_for(book)).to be_nil
  end

  it "sync grants newly linked people and does nothing without a book" do
    spouse = create(:user)
    expect { described_class.sync(household) }.not_to change(Membership, :count)
    book = described_class.call(household)
    create(:person, household: household, user: spouse)
    described_class.sync(household)
    expect(spouse.membership_for(book)).to be_editor
  end
end
