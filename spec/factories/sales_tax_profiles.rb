FactoryBot.define do
  factory :sales_tax_profile do
    business
    filing_frequency { "quarterly" }
    default_rate_bps { 925 }
    starts_on { Date.new(2026, 1, 1) }
    active { true }
  end
end
