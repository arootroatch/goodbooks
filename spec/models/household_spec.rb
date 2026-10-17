require "rails_helper"

RSpec.describe Household do
  it "cannot be created twice at the database level" do
    create(:household)
    expect { Household.create!(name: "Second") }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "finds its personal book" do
    business = create(:business)
    expect(business.household.personal_book).to be_nil
    book = create(:business, :personal)
    expect(business.household.reload.personal_book).to eq(book)
  end

  it "defaults the IRS payment URL to Direct Pay and requires https" do
    household = create(:household)
    expect(household.irs_payment_url).to eq("https://www.irs.gov/payments/direct-pay")
    household.irs_payment_url = "http://example.com"
    expect(household).not_to be_valid
    household.irs_payment_url = "javascript:alert(1)"
    expect(household).not_to be_valid
    household.irs_payment_url = "https://www.irs.gov/payments"
    expect(household).to be_valid
  end

  describe "backup_retention" do
    it "defaults to 14" do
      expect(create(:household).backup_retention).to eq(14)
    end

    it "must be a whole number from 1 to 365" do
      household = build(:household)
      [ 0, 366, 2.5, nil, "abc" ].each do |value|
        household.backup_retention = value
        expect(household).not_to be_valid, "expected #{value.inspect} to be invalid"
      end
      [ 1, 365 ].each do |value|
        household.backup_retention = value
        expect(household).to be_valid
      end
    end
  end
end
