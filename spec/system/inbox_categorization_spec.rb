require "rails_helper"

RSpec.describe "Inbox categorization", js: true do
  let!(:business) { create(:business) }
  let!(:category) { create(:category, business: business, name: "Software") }
  let!(:account) { create(:account, business: business) }
  let!(:transaction) { create(:transaction, account: account, category: nil, payee: "Adobe Inc", amount_cents: -5_499) }

  it "removes the row from the inbox without reloading the page after categorizing" do
    system_sign_in_as user_with_role("editor", business)
    visit business_inbox_path(business)

    transaction_id = "transaction_#{transaction.id}"
    expect(page).to have_css("##{transaction_id}")
    expect(page).to have_content("Adobe Inc")

    within("##{transaction_id}") do
      select "Software", from: "category_id"
      click_button "Save"
    end

    expect(page).not_to have_css("##{transaction_id}")
    expect(current_path).to eq(business_inbox_path(business))
    expect(transaction.reload.category).to eq(category)
  end
end
