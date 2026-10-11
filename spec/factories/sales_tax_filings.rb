FactoryBot.define do
  factory :sales_tax_filing do
    business { association(:sales_tax_profile).business }
    period_starts_on { Date.new(2026, 1, 1) }
    filed_on { Date.new(2026, 4, 15) }
  end
end
