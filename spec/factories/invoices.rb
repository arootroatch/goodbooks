FactoryBot.define do
  factory :invoice do
    business
    client { association(:client, business: business) }
    sequence(:number) { |n| "INV-#{1000 + n}" }
    issue_date { Date.new(2026, 1, 1) }
    due_date { Date.new(2026, 1, 31) }
    amount_cents { 120_000 }
    status { "sent" }
  end
end
