FactoryBot.define do
  factory :person do
    household { Household.first || association(:household) }
    sequence(:name) { |n| "Person #{n}" }
  end
end
