require "rails_helper"

RSpec.describe Reports::InvoiceAging do
  let(:as_of) { Date.new(2026, 10, 6) }

  def row(days_past_due, cents = 10_000, number: "INV-#{days_past_due}", business: "Pat Consulting")
    Reports::InvoiceAging::Row.new(invoice_id: days_past_due, number: number, client_name: "Acme",
                                   business_name: business, due_date: as_of - days_past_due, outstanding_cents: cents)
  end

  def bucket_for(days)
    described_class.new([ row(days) ], as_of: as_of).buckets.find { _1.rows.any? }.key
  end

  it "puts each boundary day in the right bucket" do
    expect(bucket_for(-5)).to eq("current")
    expect(bucket_for(0)).to eq("current")
    expect(bucket_for(1)).to eq("days_1_30")
    expect(bucket_for(30)).to eq("days_1_30")
    expect(bucket_for(31)).to eq("days_31_60")
    expect(bucket_for(60)).to eq("days_31_60")
    expect(bucket_for(61)).to eq("over_60")
  end

  it "always returns the four buckets in order with labels" do
    report = described_class.new([], as_of: as_of)
    expect(report.buckets.map(&:key)).to eq(%w[current days_1_30 days_31_60 over_60])
    expect(report.buckets.map(&:label)).to eq([ "Current", "1–30 days", "31–60 days", "Over 60 days" ])
    expect(report.total_cents).to eq(0)
  end

  it "totals each bucket and the report, oldest due first within a bucket" do
    report = described_class.new([ row(5, 1_000), row(20, 2_000), row(45, 4_000), row(90, 8_000) ], as_of: as_of)
    one_to_thirty = report.buckets.find { _1.key == "days_1_30" }
    expect(one_to_thirty.rows.map(&:number)).to eq(%w[INV-20 INV-5])
    expect(one_to_thirty.total_cents).to eq(3_000)
    expect(report.total_cents).to eq(15_000)
  end

  it "counts days past due" do
    expect(described_class.days_past_due(as_of - 12, as_of)).to eq(12)
    expect(described_class.days_past_due(as_of, as_of)).to eq(0)
    expect(described_class.days_past_due(as_of + 3, as_of)).to eq(0)
  end
end
