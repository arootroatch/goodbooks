require "rails_helper"

RSpec.describe TaxParameters do
  it "is estimate-ready with the 2026 published figures" do
    expect(build(:tax_parameters, :federal_2026)).to be_estimate_ready
  end

  it "is not estimate-ready with only a mileage rate" do
    expect(build(:tax_parameters)).not_to be_estimate_ready
  end

  it "saves a mileage-only year with every federal field blank" do
    params = build(:tax_parameters, year: 2025, se_earnings_percent: "", standard_deduction_mfj: "", bracket_rows: [ { "floor" => "", "rate" => "" } ])
    expect(params).to be_valid
  end

  it "takes percentages and money as text" do
    params = build(:tax_parameters, se_earnings_percent: "92.35%", standard_deduction_mfj: "32,200")
    expect(params.se_earnings_bps).to eq(9235)
    expect(params.standard_deduction_mfj_cents).to eq(3_220_000)
  end

  it "reports a bad percentage" do
    params = build(:tax_parameters, ss_rate_percent: "abc")
    expect(params).not_to be_valid
    expect(params.errors[:ss_rate_percent]).to eq([ "is not a percentage like 12.4" ])
  end

  describe "bracket rows" do
    it "drops blank rows and accepts 37 or 37%" do
      params = build(:tax_parameters, bracket_rows: [
        { "floor" => "0", "rate" => "10" }, { "floor" => "24,800", "rate" => "12%" }, { "floor" => "", "rate" => "" }
      ])
      expect(params).to be_valid
      expect(params.brackets_mfj).to eq([ { "floor_cents" => 0, "rate_bps" => 1000 }, { "floor_cents" => 2_480_000, "rate_bps" => 1200 } ])
    end

    it "rejects rows that don't start at $0 or don't rise" do
      [ [ { "floor" => "100", "rate" => "10" } ],
        [ { "floor" => "0", "rate" => "10" }, { "floor" => "0", "rate" => "12" } ] ].each do |rows|
        params = build(:tax_parameters, bracket_rows: rows)
        expect(params).not_to be_valid
        expect(params.errors[:bracket_rows]).to eq([ "must start at $0 and rise" ])
      end
    end

    it "rejects a row that isn't a number" do
      params = build(:tax_parameters, bracket_rows: [ { "floor" => "0", "rate" => "abc" } ])
      expect(params).not_to be_valid
      expect(params.errors[:bracket_rows]).to eq([ "have an amount or rate that isn't a number" ])
    end

    it "shows saved brackets as text rows" do
      params = build(:tax_parameters, :federal_2026)
      expect(params.bracket_rows.first(2)).to eq([ { "floor" => "0.00", "rate" => "10" }, { "floor" => "24800.00", "rate" => "12" } ])
    end
  end
end
