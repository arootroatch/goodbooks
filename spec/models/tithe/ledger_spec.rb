require "rails_helper"

RSpec.describe Tithe::Ledger do
  def income(date, cents) = Tithe::Ledger::Entry.new(posted_on: Date.parse(date), cents: cents, kind: :income, source: nil)
  def paid(date, cents) = Tithe::Ledger::Entry.new(posted_on: Date.parse(date), cents: cents, kind: :payment, source: nil)
  def ledger(entries, start_on: "2026-01-04", today: "2026-01-24")
    described_class.new(entries: entries, start_on: Date.parse(start_on), today: Date.parse(today))
  end

  it "starts weeks on Sunday" do
    expect(described_class.week_start(Date.new(2026, 1, 10))).to eq(Date.new(2026, 1, 4)) # Saturday
    expect(described_class.week_start(Date.new(2026, 1, 11))).to eq(Date.new(2026, 1, 11)) # Sunday
  end

  it "puts Saturday and Sunday income in different weeks and lists every week through today" do
    result = ledger([ income("2026-01-10", 10_000), income("2026-01-11", 20_000) ])
    expect(result.weeks.map(&:starts_on).map(&:iso8601)).to eq(%w[2026-01-04 2026-01-11 2026-01-18])
    expect(result.weeks.map(&:owed_cents)).to eq([ 1_000, 2_000, 0 ])
    expect(result.weeks.last.status).to eq("paid")
  end

  it "rounds once per week, half up" do
    result = ledger([ income("2026-01-05", 333), income("2026-01-06", 333), income("2026-01-07", 333) ], today: "2026-01-07")
    expect(result.weeks.sole.owed_cents).to eq(100) # 99.9 → 100, not 3 × 33
    expect(ledger([ income("2026-01-05", 1_005) ], today: "2026-01-07").owed_cents).to eq(101)
  end

  it "ignores days before a mid-week start date and anything after today" do
    result = ledger([ income("2026-01-05", 50_000), income("2026-01-08", 10_000), income("2026-01-15", 70_000) ],
                    start_on: "2026-01-07", today: "2026-01-14")
    expect(result.weeks.map(&:starts_on).map(&:iso8601)).to eq(%w[2026-01-04 2026-01-11])
    expect(result.owed_cents).to eq(1_000)
  end

  it "applies payments to the oldest week first and keeps a running balance" do
    entries = [ income("2026-01-05", 10_000), income("2026-01-12", 10_000), income("2026-01-19", 10_000), paid("2026-01-20", 2_500) ]
    result = ledger(entries)
    expect(result.weeks.map(&:status)).to eq(%w[paid paid partial])
    expect(result.weeks.map(&:paid_toward_cents)).to eq([ 1_000, 1_000, 500 ])
    expect(result.weeks.map(&:paid_cents)).to eq([ 0, 0, 2_500 ])
    expect(result.weeks.map(&:balance_cents)).to eq([ 1_000, 2_000, 500 ])
    expect(result.balance_cents).to eq(500)
    expect(result.credit_cents).to eq(0)
  end

  it "leaves later weeks open when payments run out" do
    result = ledger([ income("2026-01-05", 10_000), income("2026-01-12", 10_000), paid("2026-01-06", 400) ], today: "2026-01-17")
    expect(result.weeks.map(&:status)).to eq(%w[partial open])
  end

  it "carries an overpayment as credit" do
    result = ledger([ income("2026-01-05", 10_000), paid("2026-01-06", 1_500) ], today: "2026-01-07")
    expect(result.balance_cents).to eq(-500)
    expect(result.credit_cents).to eq(500)
    expect(result.weeks.sole.status).to eq("paid")
  end

  it "subtracts a refunded tithe from paid" do
    result = ledger([ income("2026-01-05", 10_000), paid("2026-01-06", 1_000), paid("2026-01-07", -1_000) ], today: "2026-01-08")
    expect(result.paid_cents).to eq(0)
    expect(result.weeks.sole.status).to eq("open")
  end

  it "keeps each week's entries, oldest first" do
    a = income("2026-01-06", 100)
    b = paid("2026-01-05", 10)
    expect(ledger([ a, b ], today: "2026-01-07").weeks.sole.entries).to eq([ b, a ])
  end

  it "counts year to date by the year each week ends in" do
    result = ledger([ income("2025-12-22", 10_000), income("2025-12-29", 20_000), paid("2026-01-02", 500) ],
                    start_on: "2025-12-21", today: "2026-01-05")
    expect(result.ytd_owed_cents).to eq(2_000) # week of Dec 28 ends Jan 3, 2026; plus the empty week of Jan 4
    expect(result.ytd_paid_cents).to eq(500)
  end

  it "has no weeks when the start date is after today" do
    result = ledger([], start_on: "2026-02-01", today: "2026-01-05")
    expect(result.weeks).to be_empty
    expect(result.balance_cents).to eq(0)
  end
end
