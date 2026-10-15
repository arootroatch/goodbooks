module Tax
  module Brackets
    Slice = Data.define(:rate_bps, :from_cents, :to_cents, :taxed_cents, :tax_cents)

    module_function

    def slices(taxable_cents, brackets)
      brackets.each_with_index.filter_map do |bracket, index|
        next if taxable_cents <= bracket.floor_cents

        ceiling = brackets[index + 1]&.floor_cents
        upper = ceiling ? [ taxable_cents, ceiling ].min : taxable_cents
        taxed = upper - bracket.floor_cents
        Slice.new(rate_bps: bracket.rate_bps, from_cents: bracket.floor_cents, to_cents: upper, taxed_cents: taxed,
                  tax_cents: Money.round_rational(Rational(taxed * bracket.rate_bps, 10_000)))
      end
    end

    def tax_cents(taxable_cents, brackets) = slices(taxable_cents, brackets).sum(&:tax_cents)
  end
end
