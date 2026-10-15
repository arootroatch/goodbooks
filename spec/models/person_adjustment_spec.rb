require "rails_helper"

RSpec.describe PersonAdjustment do
  let(:person) { create(:person) }

  it "defaults blank amounts to zero" do
    adjustment = described_class.create!(person:, year: 2026, se_health_insurance: "", retirement_contribution: "")
    expect(adjustment).to have_attributes(se_health_insurance_cents: 0, retirement_contribution_cents: 0, retirement_plan: nil)
  end

  it "requires a plan with a contribution" do
    adjustment = build(:person_adjustment, person:, retirement_contribution: "6,000", retirement_plan: "")
    expect(adjustment).not_to be_valid
    expect(adjustment.errors[:retirement_plan]).to eq([ "is required with a contribution" ])
  end

  it "accepts only known plans" do
    expect(build(:person_adjustment, person:, retirement_contribution: "1", retirement_plan: "ira")).not_to be_valid
  end

  it "is unique per person and year" do
    create(:person_adjustment, person:, year: 2026)
    expect(build(:person_adjustment, person:, year: 2026)).not_to be_valid
  end
end
