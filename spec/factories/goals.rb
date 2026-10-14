FactoryBot.define do
  factory :goal do
    business
    sequence(:name) { |n| "Goal #{n}" }
    kind { "payments" }
    target_cents { 30_000_00 }
    match_field { "payee" }
    match_operator { "contains" }
    match_value { "tony" }

    trait :savings do
      kind { "savings" }
      match_field { nil }
      match_operator { nil }
      match_value { nil }
      account { association :account, business: business, kind: "savings" }
    end
  end
end
