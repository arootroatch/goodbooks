require "rails_helper"

RSpec.describe "Application time zone" do
  it "uses the household's local zone so today rolls over at local midnight, not UTC midnight" do
    expect(Rails.application.config.time_zone).to eq(ENV.fetch("TIME_ZONE", "Central Time (US & Canada)"))
    travel_to Time.utc(2026, 10, 11, 1, 52) do # 8:52pm Saturday in Nashville
      expect(Date.current).to eq(Date.new(2026, 10, 10))
    end
  end
end
