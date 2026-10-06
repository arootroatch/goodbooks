FactoryBot.define do
  factory :mileage_entry do
    business
    driven_on { Date.new(2026, 3, 2) }
    purpose { "Client meeting" }
    from_location { "Home office" }
    to_location { "Client" }
    miles_tenths { 100 }
  end
end
