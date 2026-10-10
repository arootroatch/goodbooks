require "rails_helper"

RSpec.describe "Recording an invoice payment" do
  it "links the exact-match deposit and shows the invoice as paid" do
    business = create(:business)
    account = create(:account, business: business, name: "Checking")
    create(:category, :income, business: business, name: "Sales")
    invoice = create(:invoice, business: business, number: "INV-1042", amount_cents: 120_000)
    create(:transaction, account: account, amount_cents: 120_000, payee: "ACME CORP PAYMENT", posted_on: Date.current - 2)

    system_sign_in_as user_with_role("editor", business)
    visit business_invoice_path(business, invoice)
    click_on "Record payment"
    within("#exact-matches") { click_on "Link" }

    expect(page).to have_content("Payment recorded.")
    expect(page).to have_css(".badge-pos", text: "Paid")
    expect(page).to have_content("ACME CORP PAYMENT")
  end
end
