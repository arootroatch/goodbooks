FactoryBot.define do
  factory :business do
    household { Household.first || association(:household) }
    person { household.people.first || association(:person, household: household) }
    sequence(:name) { |n| "Business #{n}" }
  end
end
