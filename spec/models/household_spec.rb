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
end
