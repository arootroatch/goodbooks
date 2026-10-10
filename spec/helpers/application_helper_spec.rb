require "rails_helper"

RSpec.describe ApplicationHelper do
  describe "#money" do
    it "wraps negatives in red parentheses" do
      expect(helper.money(-5_499)).to eq('<span class="neg">($54.99)</span>')
    end

    it "returns HTML-safe output for negatives" do
      expect(helper.money(-1)).to be_html_safe
    end

    it "leaves positives and zero plain" do
      expect(helper.money(420_000)).to eq("$4,200.00")
      expect(helper.money(0)).to eq("$0.00")
    end

    it "shows a dash for nil" do
      expect(helper.money(nil)).to eq("—")
    end
  end
end
