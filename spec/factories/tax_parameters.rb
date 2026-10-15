FactoryBot.define do
  factory :tax_parameters do
    year { 2026 }
    standard_mileage_rate_tenth_cents { 725 }

    trait :federal_2026 do
      after(:build) { |params| params.assign_attributes(TaxParameters::Published.fetch(2026).except(:standard_mileage_rate_tenth_cents)) }
    end
  end
end
