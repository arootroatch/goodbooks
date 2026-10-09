module Invoices
  # One payment's share of an invoice's sales tax, rounded once; the completing payment absorbs rounding.
  module TaxShare
    def self.call(invoice_amount_cents:, invoice_tax_cents:, paid_before_cents:, shares_before_cents:, payment_cents:)
      return 0 if invoice_tax_cents.zero?
      return invoice_tax_cents - shares_before_cents if paid_before_cents + payment_cents == invoice_amount_cents

      Money.round_rational(Rational(payment_cents * invoice_tax_cents, invoice_amount_cents))
    end
  end
end
