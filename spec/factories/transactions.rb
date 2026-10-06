FactoryBot.define do
  factory :transaction do
    account
    posted_on { Date.new(2026, 1, 15) }
    amount_cents { -1000 }
    payee { "Office Depot" }
  end
end
