FactoryBot.define do
  factory :account do
    business
    sequence(:name) { |n| "Account #{n}" }
    source { "manual" }
    kind { "checking" }

    trait :csv do
      source { "csv" }
    end

    trait :plaid do
      source { "plaid" }
      plaid_item { association(:plaid_item, household: business.household) }
      sequence(:plaid_account_id) { |n| "plaid-account-#{n}" }
    end
  end
end
