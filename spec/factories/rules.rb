FactoryBot.define do
  factory :rule do
    business
    field { "payee" }
    operator { "contains" }
    value { "adobe" }
    outcome { "categorize" }
    category { association :category, business: business }
  end
end
