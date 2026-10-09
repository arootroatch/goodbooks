require "rails_helper"

RSpec.describe "Rows on Plaid-fed accounts" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, :plaid, business: business, name: "Checking") }
  let!(:manual_row) { create(:transaction, account: account, payee: "TYPED BY HAND", amount_cents: -1500) }
  let!(:bank_row) { create(:transaction, account: account, payee: "FROM PLAID", amount_cents: -2500, plaid_transaction_id: "p-1") }

  before { sign_in_as user_with_role("editor", business) }

  it "keeps a hand-entered row editable and deletable" do
    get edit_business_transaction_path(business, manual_row)
    expect(response.body).not_to include("(imported, read-only)")
    patch business_transaction_path(business, manual_row), params: { transaction: { payee: "FIXED", amount: "16.00", direction: "out" } }
    expect(manual_row.reload.payee).to eq("FIXED")
    expect(manual_row.amount_cents).to eq(-1600)
    delete business_transaction_path(business, manual_row)
    expect(Transaction.exists?(manual_row.id)).to be(false)
  end

  it "keeps a Plaid row's date, amount, and payee read-only" do
    get edit_business_transaction_path(business, bank_row)
    expect(response.body).to include("(imported, read-only)")
    patch business_transaction_path(business, bank_row), params: { transaction: { payee: "HACKED", amount: "1.00", memo: "note" } }
    expect(bank_row.reload.payee).to eq("FROM PLAID")
    expect(bank_row.amount_cents).to eq(-2500)
    expect(bank_row.memo).to eq("note")
    delete business_transaction_path(business, bank_row)
    expect(Transaction.exists?(bank_row.id)).to be(true)
  end

  it "offers CSV upload on a Plaid-fed account but not on a manual one" do
    get business_accounts_path(business)
    expect(response.body).to include(new_business_account_csv_import_path(business, account))
    get new_business_account_csv_import_path(business, account)
    expect(response).to have_http_status(:ok)
    cash = business.accounts.create!(name: "Petty", source: "manual", kind: "cash")
    get new_business_account_csv_import_path(business, cash)
    expect(response).to have_http_status(:not_found)
  end
end
