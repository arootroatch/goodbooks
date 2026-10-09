require "rails_helper"

RSpec.describe SalesTax::Calendar do
  def holidays(*dates)
    Object.new.tap do |list|
      list.define_singleton_method(:for) { |year| dates.select { _1.year == year } }
    end
  end

  def calendar(starts_on, frequency, today, list = holidays)
    described_class.new(starts_on: starts_on, frequency: frequency, today: today, holidays: list)
  end

  it "lists calendar quarters from the one containing the start through the one containing today" do
    periods = calendar(Date.new(2026, 2, 14), "quarterly", Date.new(2026, 10, 8)).periods
    expect(periods.map(&:starts_on)).to eq([ Date.new(2026, 1, 1), Date.new(2026, 4, 1), Date.new(2026, 7, 1), Date.new(2026, 10, 1) ])
    expect(periods.first.ends_on).to eq(Date.new(2026, 3, 31))
    expect(periods.map(&:label)).to eq([ "Q1 2026", "Q2 2026", "Q3 2026", "Q4 2026" ])
  end

  it "lists months and years" do
    months = calendar(Date.new(2026, 8, 31), "monthly", Date.new(2026, 10, 1)).periods
    expect(months.map { [ _1.starts_on, _1.ends_on ] }).to eq([
      [ Date.new(2026, 8, 1), Date.new(2026, 8, 31) ], [ Date.new(2026, 9, 1), Date.new(2026, 9, 30) ], [ Date.new(2026, 10, 1), Date.new(2026, 10, 31) ]
    ])
    expect(months.first.label).to eq("Aug 2026")
    years = calendar(Date.new(2025, 6, 1), "annual", Date.new(2026, 3, 1)).periods
    expect(years.map { [ _1.starts_on, _1.ends_on, _1.label ] }).to eq([
      [ Date.new(2025, 1, 1), Date.new(2025, 12, 31), "2025" ], [ Date.new(2026, 1, 1), Date.new(2026, 12, 31), "2026" ]
    ])
  end

  it "is empty when today is before the first period" do
    expect(calendar(Date.new(2026, 5, 1), "monthly", Date.new(2026, 4, 30)).periods).to eq([])
  end

  {
    "a weekday" => [ Date.new(2026, 9, 30), Date.new(2026, 10, 20) ],
    "a Saturday" => [ Date.new(2026, 5, 31), Date.new(2026, 6, 22) ],
    "a Sunday" => [ Date.new(2026, 8, 31), Date.new(2026, 9, 21) ]
  }.each do |label, (ends_on, due_on)|
    it "rolls a 20th that falls on #{label}" do
      expect(described_class.due_on(ends_on, holidays: holidays)).to eq(due_on)
    end
  end

  it "rolls past a holiday, and past a holiday followed by a weekend" do
    expect(described_class.due_on(Date.new(2026, 9, 30), holidays: holidays(Date.new(2026, 10, 20)))).to eq(Date.new(2026, 10, 21))
    expect(described_class.due_on(Date.new(2026, 10, 31), holidays: holidays(Date.new(2026, 11, 20)))).to eq(Date.new(2026, 11, 23))
  end

  it "finds the period for a date and recognizes period starts" do
    cal = calendar(Date.new(2026, 1, 1), "quarterly", Date.new(2026, 10, 8))
    expect(cal.period_for(Date.new(2026, 5, 9)).starts_on).to eq(Date.new(2026, 4, 1))
    expect(cal.period_for(Date.new(2025, 12, 31))).to be_nil
    expect(cal.include_start?(Date.new(2026, 4, 1))).to be(true)
    expect(cal.include_start?(Date.new(2026, 4, 2))).to be(false)
    expect(cal.include_start?(Date.new(2025, 10, 1))).to be(false)
    expect(cal.include_start?(nil)).to be(false)
  end
end
