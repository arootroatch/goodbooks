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
end
