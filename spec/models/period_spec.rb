require "rails_helper"

RSpec.describe Period do
  let(:today) { Date.new(2026, 10, 10) }

  def period(kind = nil, on = nil) = described_class.from_params({ period: kind, on: on }, today:)

  describe ".from_params" do
    it "defaults to the current year" do
      expect(period.kind).to eq("year")
      expect(period.range).to eq(Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
    end

    it "covers the whole month, quarter, or year containing the date" do
      expect(period("month", "2026-02-14").range).to eq(Date.new(2026, 2, 1)..Date.new(2026, 2, 28))
      expect(period("quarter", "2026-08-03").range).to eq(Date.new(2026, 7, 1)..Date.new(2026, 9, 30))
      expect(period("year", "2025-06-01").range).to eq(Date.new(2025, 1, 1)..Date.new(2025, 12, 31))
    end

    it "falls back to today for a bad date and to year for an unknown kind" do
      expect(period("month", "nope").range.first).to eq(Date.new(2026, 10, 1))
      expect(period("decade", "2026-02-14").kind).to eq("year")
    end
  end

  describe "#label and #dates" do
    it "names exactly what is being viewed" do
      expect(period("month", "2026-10-01").label).to eq("October 2026")
      expect(period("quarter", "2026-10-01").label).to eq("Q4 2026")
      expect(period("year", "2026-10-01").label).to eq("2026")
      expect(period("quarter", "2026-10-01").dates).to eq("Oct 1 – Dec 31, 2026")
    end
  end

  describe "stepping" do
    it "moves to the neighbouring period of the same kind" do
      expect(period("quarter", "2026-01-20").previous.label).to eq("Q4 2025")
      expect(period("month", "2026-09-05").next.label).to eq("October 2026")
    end

    it "has no next period once the following one would start after today" do
      expect(period("month", "2026-09-05").next?).to be true
      expect(period("month", "2026-10-05").next?).to be false
    end
  end

  describe "#switch_to" do
    it "keeps today when the current period contains it, otherwise starts at the period's beginning" do
      expect(period("year").switch_to("quarter").label).to eq("Q4 2026")
      expect(period("year", "2025-03-01").switch_to("month").label).to eq("January 2025")
    end
  end

  describe "#to_params" do
    it "round-trips through from_params" do
      params = period("quarter", "2026-08-03").to_params
      expect(params).to eq(period: "quarter", on: "2026-07-01")
      expect(described_class.from_params(params, today:).label).to eq("Q3 2026")
    end
  end

  describe "#buckets" do
    it "splits a month into Monday-start weeks clipped to the month" do
      buckets = period("month", "2026-10-01").buckets
      expect(buckets.map(&:label)).to eq([ "Oct 1", "Oct 5", "Oct 12", "Oct 19", "Oct 26" ])
      expect(buckets.first.range).to eq(Date.new(2026, 10, 1)..Date.new(2026, 10, 4))
      expect(buckets.last.range).to eq(Date.new(2026, 10, 26)..Date.new(2026, 10, 31))
    end

    it "splits quarters and years into months" do
      expect(period("quarter", "2026-10-01").buckets.map(&:label)).to eq(%w[Oct Nov Dec])
      expect(period("year").buckets.size).to eq(12)
    end
  end

  describe "#bucket_unit" do
    it "names the bucket size" do
      expect(period("month").bucket_unit).to eq("week")
      expect(period("quarter").bucket_unit).to eq("month")
    end
  end

  describe "#bucket_in_progress" do
    it "is the index of the bucket containing today, or nil" do
      expect(period("year").bucket_in_progress).to eq(9)
      expect(period("month", "2026-10-01").bucket_in_progress).to eq(1)
      expect(period("year", "2025-01-01").bucket_in_progress).to be_nil
    end
  end
end
