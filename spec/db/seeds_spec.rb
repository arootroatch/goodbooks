require "rails_helper"

RSpec.describe "db/seeds.rb" do
  it "creates reference data idempotently" do
    2.times { load Rails.root.join("db/seeds.rb") }
    expect(TaxParameters.for_year(2026).standard_mileage_rate_tenth_cents).to eq(725)
    expect(TaxParameters.count).to eq(1)
  end
end
