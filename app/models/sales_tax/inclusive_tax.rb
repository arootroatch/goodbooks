module SalesTax
  # Tax inside a tax-inclusive amount: base × r / (1 + r), rounded once.
  module InclusiveTax
    def self.call(gross_cents:, rate_bps:)
      return 0 unless gross_cents.positive?

      Money.round_rational(Rational(gross_cents * rate_bps, 10_000 + rate_bps))
    end
  end
end
