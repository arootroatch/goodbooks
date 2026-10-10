require "rails_helper"

RSpec.describe ChartsHelper do
  def chart(labels: %w[Jan Feb], income: [ 100_000, 200_000 ], expense: [ 50_000, 0 ], **opts)
    html = helper.bar_chart(labels:, label: "Monthly income and expenses",
                            series: [ { key: "income", name: "Income", values: income },
                                      { key: "expense", name: "Expenses", values: expense } ], **opts)
    Capybara.string(html)
  end

  describe "#bar_chart" do
    it "draws one bar per positive value" do
      expect(chart).to have_css("rect.bar", count: 3, visible: :all)
      expect(chart).to have_css("rect.bar-income", count: 2, visible: :all)
      expect(chart).to have_css("rect.bar-expense", count: 1, visible: :all)
    end

    it "scales bar heights to a rounded maximum" do
      heights = chart.all("rect.bar-income", visible: :all).map { _1[:height].to_f }
      expect(heights).to eq([ 90.0, 180.0 ]) # max 200_000 → full plot height of 180
    end

    it "titles every bar with its month, series, and amount" do
      expect(chart).to have_css("rect.bar-income title", text: "Feb income: $2,000.00", visible: :all)
      expect(chart).to have_css("rect.bar-expense title", text: "Jan expenses: $500.00", visible: :all)
    end

    it "labels the axes" do
      texts = chart.all("text.chart-axis", visible: :all).map { _1.text(:all) }
      expect(texts).to include("Jan", "Feb", "$0", "$1k", "$2k")
    end

    it "is an accessible image" do
      svg = chart.find("svg", visible: :all)
      expect(svg[:role]).to eq("img")
      expect(svg["aria-label"]).to eq("Monthly income and expenses")
      expect(svg[:viewbox] || svg[:viewBox]).to eq("0 0 600 220")
    end

    it "draws axes but no bars when every value is zero" do
      zero = chart(income: [ 0, 0 ], expense: [ 0, 0 ])
      expect(zero).to have_no_css("rect.bar", visible: :all)
      expect(zero).to have_css("line.chart-grid", count: 5, visible: :all)
    end

    it "handles no labels at all" do
      empty = chart(labels: [], income: [], expense: [])
      expect(empty).to have_no_css("rect.bar", visible: :all)
      expect(empty).to have_css("line.chart-grid", count: 5, visible: :all)
    end

    it "fades only the last group when asked" do
      faded = chart(faded_last: true)
      expect(faded).to have_css("rect.faded", count: 1, visible: :all)
      expect(faded).to have_css("rect.faded title", text: "Feb income", visible: :all)
      expect(chart).to have_no_css("rect.faded", visible: :all)
    end
  end

  describe "#compact_dollars" do
    it "abbreviates thousands" do
      expect(helper.compact_dollars(0)).to eq("$0")
      expect(helper.compact_dollars(50_000)).to eq("$500")
      expect(helper.compact_dollars(250_000)).to eq("$2.5k")
      expect(helper.compact_dollars(2_000_000)).to eq("$20k")
    end
  end
end
