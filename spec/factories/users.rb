FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    name { "Test User" }
    password { AuthHelpers::PASSWORD }
    otp_secret { ROTP::Base32.random }
    otp_enabled_at { Time.current }

    trait :without_otp do
      otp_secret { nil }
      otp_enabled_at { nil }
    end

    trait :household_owner do
      after(:create) do |user|
        household = create(:household)
        create(:person, user: user, household: household)
      end
    end
  end
end
