require "rails_helper"

RSpec.describe "db/seeds.rb" do
  it "creates reference data idempotently" do
    2.times { load Rails.root.join("db/seeds.rb") }
    params = TaxParameters.for_year(2026)
    expect(params.standard_mileage_rate_tenth_cents).to eq(725)
    expect(params).to be_estimate_ready
    expect(TaxParameters.count).to eq(1)
  end

  it "fills blank federal fields on an existing row without overwriting edits" do
    TaxParameters.create!(year: 2026, standard_mileage_rate_tenth_cents: 700, ss_wage_base_cents: 1)
    load Rails.root.join("db/seeds.rb")
    params = TaxParameters.for_year(2026)
    expect(params.standard_mileage_rate_tenth_cents).to eq(700)
    expect(params.ss_wage_base_cents).to eq(1)
    expect(params.standard_deduction_mfj_cents).to eq(3_220_000)
  end
end
