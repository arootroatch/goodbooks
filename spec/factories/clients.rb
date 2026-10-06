FactoryBot.define do
  factory :client do
    business
    sequence(:name) { |n| "Client #{n}" }
  end
end
