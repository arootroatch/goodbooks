FactoryBot.define do
  factory :category do
    business
    sequence(:name) { |n| "Category #{n}" }
    kind { "expense" }
    schedule_c_line { business.personal? ? nil : "18" }

    trait :income do
      kind { "income" }
      schedule_c_line { business.personal? ? nil : "1" }
    end
  end
end
