require "rails_helper"

RSpec.describe "Inbox invoice hint", js: true do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business) }
  let!(:sales) { create(:category, :income, business: business, name: "Sales") }
  let!(:invoice) { create(:invoice, business: business, number: "INV-1042", amount_cents: 120_000) }
  let!(:deposit) { create(:transaction, account: account, amount_cents: 120_000, payee: "ACME CORP PAYMENT") }

  it "marks the invoice paid and removes the row without reloading the page" do
    system_sign_in_as user_with_role("editor", business)
    visit business_inbox_path(business)
    page.execute_script("window.__noReload = true")

    row = "#transaction_#{deposit.id}"
    within(row) do
      expect(page).to have_content("Matches INV-1042")
      click_button "Mark paid"
    end

    expect(page).not_to have_css(row)
    expect(page.evaluate_script("window.__noReload")).to be(true)
    expect(invoice.reload).to be_paid
  end
end
