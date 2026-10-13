FactoryBot.define do
  factory :home_office do
    business
    year { 2026 }
    calculation { "simplified" }
    office_sqft { 200 }
  end
end
