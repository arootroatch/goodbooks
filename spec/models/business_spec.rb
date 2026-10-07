require "rails_helper"

RSpec.describe Business do
  it "defaults to a business that needs a person" do
    business = build(:business, person: nil)
    expect(business).to be_business
    expect(business).not_to be_valid
    expect(business.errors[:person]).to be_present
  end

  it "allows one personal book per household, with no person" do
    book = create(:business, :personal)
    expect(book).to be_personal
    expect(book.person).to be_nil
    expect(Business.personal).to eq([ book ])
    expect(Business.business_kind).not_to include(book)
    expect(build(:business, :personal)).not_to be_valid
  end

  it "rejects a person on the personal book" do
    expect(build(:business, :personal, person: create(:person))).not_to be_valid
  end

  it "accepts a past or today tithe start date only on the personal book" do
    book = create(:business, :personal)
    expect(book.update(tithe_start_on: Date.current)).to be(true)
    expect(book.update(tithe_start_on: Date.current + 1)).to be(false)
    expect(book.errors[:tithe_start_on]).to include("can't be in the future")
    expect(build(:business, tithe_start_on: Date.current - 1)).not_to be_valid
  end

  it "refuses to archive the personal book" do
    book = create(:business, :personal)
    expect(book.update(archived_at: Time.current)).to be(false)
  end
end
