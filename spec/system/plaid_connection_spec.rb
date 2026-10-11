require "rails_helper"

RSpec.describe "Connecting a bank", type: :system, js: true do
  include ActiveJob::TestHelper

  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:owner) { user_with_role("owner", business) }
  let!(:csv) { create(:account, :csv, business: business, name: "Business Checking") }
  let!(:csv_row) do
    create(:transaction, account: csv, posted_on: Date.current - 5, amount_cents: -4_500, payee: "SQ *COFFEE 8475", external_id: "h1")
  end
  let!(:software) { create(:category, business: business, name: "Software") }
  let!(:rule) { create(:rule, business: business, value: "adobe", category: software) }

  def choose_in(row, label, option) = within(row) { find("select[aria-label='#{label}']").select(option) }

  it "links, assigns, syncs without duplicating CSV history, and resolves a review" do
    system_sign_in_as owner
    click_on "Banks"
    click_on "Connect a bank"
    click_on "Connect with Plaid"
    expect(page).to have_content("Assign Demo Bank accounts")

    item = PlaidItem.sole
    plaid_gateway.add_page(item.access_token, added: [
      FakePlaidGateway.plaid_txn("p-coffee", account_id: "fake-checking", amount: 45.0, date: Date.current - 4, name: "SQ *COFFEE", merchant_name: "Coffee"),
      FakePlaidGateway.plaid_txn("p-adobe", account_id: "fake-checking", amount: 54.99, date: Date.current - 2, name: "ADOBE"),
      FakePlaidGateway.plaid_txn("p-kroger", account_id: "fake-card", amount: 80.0, date: Date.current - 1, name: "KROGER")
    ])
    choose_in("#plaid_account_fake-checking", "What to do with Plaid Checking", "Existing account")
    choose_in("#plaid_account_fake-checking", "Existing account for Plaid Checking", "Business Checking")
    choose_in("#plaid_account_fake-card", "What to do with Plaid Credit Card", "New account")
    within("#plaid_account_fake-card") { find("input[aria-label='Name for Plaid Credit Card']").fill_in(with: "Visa") }
    click_on "Save assignments"
    expect(page).to have_content("Accounts saved. Syncing now.")
    perform_enqueued_jobs
    expect(csv.transactions.count).to eq(2)
    expect(csv_row.reload.plaid_transaction_id).to eq("p-coffee")
    expect(csv.transactions.find_by!(plaid_transaction_id: "p-adobe").category).to eq(software)

    visit business_inbox_path(business)
    expect(page).to have_content("KROGER")
    expect(page).not_to have_content("ADOBE")

    csv_row.update!(category: software, categorized_by: "user")
    plaid_gateway.add_page(item.access_token, removed: [ { transaction_id: "p-coffee", account_id: "fake-checking" } ])
    visit plaid_item_path(item)
    click_on "Sync now"
    expect(page).to have_content("Sync started.")
    perform_enqueued_jobs
    visit business_inbox_path(business)
    expect(page).to have_content("Removed by the bank")
    within("#review_transaction_#{csv_row.id}") { click_on "Keep" }
    expect(page).not_to have_css("#review_transaction_#{csv_row.id}")
    expect(csv_row.reload.review_reason).to be_nil
  end
end
