require "rails_helper"

RSpec.describe MileageDeduction do
  it "multiplies tenths of miles by tenths of cents and rounds once, half up" do
    # 123.4 miles × 72.5¢ = 8946.5¢ → 8947¢
    expect(MileageDeduction.cents(miles_tenths: 1234, rate_tenth_cents: 725)).to eq(8947)
  end

  it "is zero for zero miles" do
    expect(MileageDeduction.cents(miles_tenths: 0, rate_tenth_cents: 725)).to eq(0)
  end
end
