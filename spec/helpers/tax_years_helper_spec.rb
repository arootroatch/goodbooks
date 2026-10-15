require "rails_helper"

RSpec.describe TaxYearsHelper do
  describe "#tax_period_label" do
    def worksheet(quarter, elapsed_days = nil) = Struct.new(:quarter, :elapsed_days).new(quarter, elapsed_days)

    it "names the annualization factor of a full period" do
      expect((1..4).map { helper.tax_period_label(worksheet(_1)) })
        .to eq([ "annualized ×4", "annualized ×2.4", "annualized ×1.5", "annualized ×1" ])
    end

    it "describes a period still in progress" do
      expect(helper.tax_period_label(worksheet(2, 0))).to eq("no activity yet")
      expect(helper.tax_period_label(worksheet(2, 1))).to eq("projected from 1 day")
      expect(helper.tax_period_label(worksheet(2, 121))).to eq("projected from 121 days")
    end
  end
end
