module MileageDeduction
  def self.cents(miles_tenths:, rate_tenth_cents:)
    Money.round_rational(Rational(miles_tenths * rate_tenth_cents, 100))
  end
end
