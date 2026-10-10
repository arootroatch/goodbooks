require "rails_helper"

RSpec.describe OverviewHelper do
  describe "#share_of_income" do
    it "formats a whole percentage" do
      expect(helper.share_of_income(250_000, 1_000_000)).to eq("25% of income")
    end

    it "is nil without income" do
      expect(helper.share_of_income(250_000, 0)).to be_nil
    end
  end
end
