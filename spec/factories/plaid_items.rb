FactoryBot.define do
  factory :plaid_item do
    household { Household.first || association(:household) }
    created_by { association(:user) }
    institution_name { "Demo Bank" }
    sequence(:item_id) { |n| "item-#{n}" }
    sequence(:access_token) { |n| "access-sandbox-#{n}" }
  end
end
