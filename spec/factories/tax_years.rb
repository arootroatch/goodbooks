FactoryBot.define do
  factory :tax_year do
    household { Household.first || association(:household) }
    year { 2026 }
  end
end
