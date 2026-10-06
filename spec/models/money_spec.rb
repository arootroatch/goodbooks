require "rails_helper"

RSpec.describe Money do
  describe ".parse" do
    {
      "12" => 1200,
      "12.5" => 1250,
      "12.34" => 1234,
      "$1,234.56" => 123456,
      "-5.00" => -500,
      "(5.00)" => -500,
      "($1,000)" => -100000,
      "$-5" => -500,
      ".5" => 50,
      " 7 " => 700,
      "0" => 0
    }.each do |input, cents|
      it "parses #{input.inspect} as #{cents} cents" do
        expect(Money.parse(input).cents).to eq(cents)
      end
    end

    ["", "   ", nil, "abc", "1.234", "--5", "1.2.3", "$", "12a", "(-5)", "12,50", "1,23", ",5", "5,", "1,,000"].each do |input|
      it "rejects #{input.inspect}" do
        expect { Money.parse(input) }.to raise_error(Money::ParseError)
      end
    end

    it "says blank input can't be blank" do
      expect { Money.parse("") }.to raise_error(Money::ParseError, "can't be blank")
    end

    it "says garbage is not a valid amount" do
      expect { Money.parse("abc") }.to raise_error(Money::ParseError, "is not a valid amount")
    end
  end

  describe "#to_s" do
    it { expect(Money.new(123456).to_s).to eq("$1,234.56") }
    it { expect(Money.new(-5).to_s).to eq("-$0.05") }
    it { expect(Money.new(0).to_s).to eq("$0.00") }
    it { expect(Money.new(100_000_000).to_s).to eq("$1,000,000.00") }
  end

  describe "#to_input" do
    it { expect(Money.new(-123456).to_input).to eq("-1234.56") }
    it { expect(Money.new(7).to_input).to eq("0.07") }
  end

  describe ".round_rational" do
    it { expect(Money.round_rational(Rational(5, 2))).to eq(3) }
    it { expect(Money.round_rational(Rational(-5, 2))).to eq(-3) }
    it { expect(Money.round_rational(Rational(249, 100))).to eq(2) }
    it { expect(Money.round_rational(Rational(-249, 100))).to eq(-2) }
    it { expect(Money.round_rational(7)).to eq(7) }
  end

  it "compares by cents" do
    expect(Money.new(5)).to eq(Money.new(5))
    expect(Money.new(5)).to be < Money.new(6)
  end
end
