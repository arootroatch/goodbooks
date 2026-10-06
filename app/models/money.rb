class Money
  include Comparable

  class ParseError < ArgumentError; end

  attr_reader :cents

  def self.round_rational(value)
    rational = value.to_r
    sign = rational.negative? ? -1 : 1
    sign * (rational.abs + Rational(1, 2)).floor
  end

  def self.parse(input)
    text = input.to_s.strip
    raise ParseError, "can't be blank" if text.empty?
    raise ParseError, "is not a valid amount" if text.count("-") > 1

    negative = false
    if (wrapped = text.match(/\A\((.*)\)\z/))
      raise ParseError, "is not a valid amount" if wrapped[1].include?("-")
      negative = true
      text = wrapped[1].strip
    end
    if text.start_with?("-")
      negative = true
      text = text.delete_prefix("-").strip
    end
    text = text.delete_prefix("$")
    if text.start_with?("-")
      negative = true
      text = text.delete_prefix("-")
    end

    # Validate comma placement before stripping
    integer_part, fractional_part = text.split(".")
    raise ParseError, "is not a valid amount" if text.include?(",") && !integer_part.match?(/\A\d{1,3}(,\d{3})+\z/)

    text = text.delete(",")

    match = text.match(/\A(\d*)(?:\.(\d{1,2}))?\z/)
    raise ParseError, "is not a valid amount" if match.nil? || (match[1].empty? && match[2].nil?)

    cents = match[1].to_i * 100 + match[2].to_s.ljust(2, "0").to_i
    new(negative ? -cents : cents)
  end

  def initialize(cents)
    @cents = Integer(cents)
  end

  def <=>(other)
    cents <=> other.cents if other.is_a?(Money)
  end

  def to_s
    "#{"-" if cents.negative?}$#{grouped_dollars}.#{padded_cents}"
  end

  def to_input
    "#{"-" if cents.negative?}#{cents.abs / 100}.#{padded_cents}"
  end

  private

  def grouped_dollars
    (cents.abs / 100).to_s.reverse.scan(/\d{1,3}/).join(",").reverse
  end

  def padded_cents
    format("%02d", cents.abs % 100)
  end
end
