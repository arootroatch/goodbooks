require "rails_helper"

RSpec.describe SalesTax::Holidays do
  {
    2025 => [ Date.new(2025, 1, 20), Date.new(2025, 2, 17), Date.new(2025, 4, 18) ],
    2026 => [ Date.new(2026, 1, 19), Date.new(2026, 2, 16), Date.new(2026, 4, 3) ],
    2027 => [ Date.new(2027, 1, 18), Date.new(2027, 2, 15), Date.new(2027, 3, 26) ],
    2057 => [ Date.new(2057, 1, 15), Date.new(2057, 2, 19), Date.new(2057, 4, 20) ]
  }.each do |year, dates|
    it "computes MLK Day, Presidents' Day, and Good Friday for #{year}" do
      expect(described_class.for(year)).to eq(dates)
    end
  end

  it "works for any year without a list" do
    expect(described_class.for(2199).size).to eq(3)
  end

  it "rolls real due dates past MLK Day, Presidents' Day, and Good Friday" do
    expect(SalesTax::Calendar.due_on(Date.new(2024, 12, 31))).to eq(Date.new(2025, 1, 21))
    expect(SalesTax::Calendar.due_on(Date.new(2034, 1, 31))).to eq(Date.new(2034, 2, 21))
    expect(SalesTax::Calendar.due_on(Date.new(2057, 3, 31))).to eq(Date.new(2057, 4, 23))
  end
end
