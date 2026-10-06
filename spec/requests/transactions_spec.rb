require "rails_helper"

RSpec.describe "Transactions" do
  let!(:business) { create(:business) }
  let!(:cash) { create(:account, business: business, name: "Cash", source: "manual", kind: "cash") }
  let!(:bank) { create(:account, :csv, business: business, name: "Checking") }
  let!(:category) { create(:category, business: business, name: "Supplies", schedule_c_line: "22") }
  let!(:imported) { create(:transaction, account: bank, payee: "BANK PAYEE", amount_cents: -2000, external_id: "x1") }

  it "lists for viewers, filtered" do
    sign_in_as user_with_role("viewer", business)
    get business_transactions_path(business, q: "bank")
    expect(response.body).to include("BANK PAYEE")
  end

  it "lets editors add a manual cash expense" do
    sign_in_as user_with_role("editor", business)
    post business_transactions_path(business), params: { transaction: {
      account_id: cash.id, posted_on: "2026-02-03", payee: "Hardware store", amount: "$1,234.50", direction: "out", category_id: category.id
    } }
    expect(response).to redirect_to(business_transactions_path(business))
    txn = cash.transactions.sole
    expect(txn.amount_cents).to eq(-123450)
    expect(txn.categorized_by).to eq("user")
  end

  it "re-renders on a bad amount" do
    sign_in_as user_with_role("editor", business)
    post business_transactions_path(business), params: { transaction: {
      account_id: cash.id, posted_on: "2026-02-03", payee: "X", amount: "abc", direction: "out"
    } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("is not a valid amount")
  end

  it "does not add manual entries to imported accounts" do
    sign_in_as user_with_role("editor", business)
    post business_transactions_path(business), params: { transaction: {
      account_id: bank.id, posted_on: "2026-02-03", payee: "X", amount: "1", direction: "out"
    } }
    expect(response).to have_http_status(:not_found)
  end

  it "only lets imported transactions change category, transfer, memo, and excluded" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_path(business, imported), params: { transaction: {
      amount: "999", payee: "Changed", memo: "note", category_id: category.id
    } }
    imported.reload
    expect(imported.amount_cents).to eq(-2000)
    expect(imported.payee).to eq("BANK PAYEE")
    expect(imported.memo).to eq("note")
    expect(imported.category).to eq(category)
  end

  context "with an archived category" do
    let!(:old) { create(:category, business: business, name: "Old", archived_at: Time.current) }

    before { imported.update!(category: old, categorized_by: "user") }

    it "keeps the archived category selected on edit" do
      sign_in_as user_with_role("editor", business)
      get edit_business_transaction_path(business, imported)
      expect(response.body).to include(%(<option selected="selected" value="#{old.id}"))
    end

    it "keeps the category when the form is saved" do
      sign_in_as user_with_role("editor", business)
      patch business_transaction_path(business, imported), params: { transaction: { memo: "n", category_id: old.id, transfer: "0" } }
      expect(imported.reload.category).to eq(old)
    end
  end

  it "marks user-categorized only when category or transfer changes" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_path(business, imported), params: { transaction: { memo: "note", category_id: "", transfer: "0" } }
    expect(imported.reload.categorized_by).to be_nil
    patch business_transaction_path(business, imported), params: { transaction: { memo: "note", category_id: category.id, transfer: "0" } }
    expect(imported.reload.categorized_by).to eq("user")
  end

  it "deletes manual transactions but not imported ones" do
    manual = create(:transaction, account: cash)
    sign_in_as user_with_role("editor", business)
    delete business_transaction_path(business, manual)
    expect(Transaction.exists?(manual.id)).to be(false)
    delete business_transaction_path(business, imported)
    expect(Transaction.exists?(imported.id)).to be(true)
  end

  it "forbids viewers from writing" do
    sign_in_as user_with_role("viewer", business)
    post business_transactions_path(business), params: { transaction: { account_id: cash.id, payee: "X", amount: "1" } }
    expect(response).to have_http_status(:forbidden)
    patch business_transaction_path(business, imported), params: { transaction: { memo: "x" } }
    expect(response).to have_http_status(:forbidden)
    delete business_transaction_path(business, imported)
    expect(response).to have_http_status(:forbidden)
  end

  it "is not found for another business's transaction" do
    sign_in_as user_with_role("editor", business)
    get edit_business_transaction_path(business, create(:transaction))
    expect(response).to have_http_status(:not_found)
  end
end
