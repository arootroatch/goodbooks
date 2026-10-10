require "rails_helper"

RSpec.describe OverviewHelper do
  let(:today) { Date.new(2026, 5, 20) }

  describe "#period_options" do
    it "offers month, quarter, and year to date, marking the one matching the range" do
      options = helper.period_options(Date.new(2026, 4, 1)..today, today:)
      expect(options).to eq([
        [ "Month", { from: "2026-05-01", to: "2026-05-20" }, false ],
        [ "Quarter", { from: "2026-04-01", to: "2026-05-20" }, true ],
        [ "YTD", { from: "2026-01-01", to: "2026-05-20" }, false ]
      ])
    end

    it "marks nothing for a custom range" do
      expect(helper.period_options(Date.new(2025, 1, 1)..Date.new(2025, 6, 30), today:).map(&:last)).to all(be false)
    end
  end

  describe "#share_of_income" do
    it "formats a whole percentage" do
      expect(helper.share_of_income(250_000, 1_000_000)).to eq("25% of income")
    end

    it "is nil without income" do
      expect(helper.share_of_income(250_000, 0)).to be_nil
    end
  end

  describe "#month_in_progress?" do
    it "is true only for the current calendar month" do
      expect(helper.month_in_progress?(Date.new(2026, 5, 1), today:)).to be true
      expect(helper.month_in_progress?(Date.new(2025, 5, 31), today:)).to be false
    end
  end
end
