require "rails_helper"

RSpec.describe MileageEntry do
  it "parses miles and doubles round trips" do
    entry = build(:mileage_entry, miles: "18.4", round_trip: true)
    expect(entry.miles_tenths).to eq(184)
    expect(entry.effective_miles_tenths).to eq(368)
  end

  it "reports bad miles" do
    entry = build(:mileage_entry, miles: "lots")
    expect(entry).not_to be_valid
    expect(entry.errors[:miles]).to include("must be a number with at most one decimal place")
  end

  it "requires a purpose and positive miles" do
    expect(build(:mileage_entry, purpose: "")).not_to be_valid
    expect(build(:mileage_entry, miles_tenths: 0)).not_to be_valid
  end
end
