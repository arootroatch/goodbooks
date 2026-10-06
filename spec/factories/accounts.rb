FactoryBot.define do
  factory :account do
    business
    sequence(:name) { |n| "Account #{n}" }
    source { "manual" }
    kind { "checking" }

    trait :csv do
      source { "csv" }
    end
  end
end
