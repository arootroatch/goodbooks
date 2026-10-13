FactoryBot.define do
  factory :estimated_payment do
    tax_year
    paid_on { Date.new(2026, 4, 15) }
    amount_cents { 100_000 }
  end
end
