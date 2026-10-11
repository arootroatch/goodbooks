FactoryBot.define do
  factory :business do
    household { Household.first || association(:household) }
    person { household.people.first || association(:person, household: household) }
    sequence(:name) { |n| "Business #{n}" }

    trait :personal do
      kind { "personal" }
      person { nil }
      name { "Personal" }
    end
  end
end
