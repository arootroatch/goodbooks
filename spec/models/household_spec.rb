require "rails_helper"

RSpec.describe Household do
  it "cannot be created twice at the database level" do
    create(:household)
    expect { Household.create!(name: "Second") }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
