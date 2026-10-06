FactoryBot.define do
  factory :membership do
    user
    business
    role { "viewer" }
  end
end
