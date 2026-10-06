require "rails_helper"

RSpec.describe Tenths do
  it { expect(Tenths.parse("12.3")).to eq(123) }
  it { expect(Tenths.parse("12")).to eq(120) }
  it { expect(Tenths.parse(" .5 ")).to eq(5) }
  it { expect(Tenths.parse("1,200.5")).to eq(12005) }

  ["", "abc", "1.25", "-3", "1.2.3"].each do |bad|
    it "rejects #{bad.inspect}" do
      expect { Tenths.parse(bad) }.to raise_error(Tenths::ParseError)
    end
  end

  it { expect(Tenths.format(725)).to eq("72.5") }
  it { expect(Tenths.format(5)).to eq("0.5") }
end
