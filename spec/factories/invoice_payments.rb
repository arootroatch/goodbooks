FactoryBot.define do
  factory :invoice_payment do
    invoice
    deposit do
      business = invoice.business
      income = business.categories.find_by(kind: "income") || association(:category, :income, business: business)
      association(:transaction, account: association(:account, business: business), amount_cents: invoice.amount_cents,
                                payee: "CLIENT PAYMENT", category: income, categorized_by: "user")
    end
    amount_cents { invoice.amount_cents }
  end
end
