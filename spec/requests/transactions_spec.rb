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

  describe "sales tax fields" do
    let!(:business) { create(:business) }
    let!(:profile) { create(:sales_tax_profile, business: business) }
    let!(:sales) { create(:category, :income, business: business, name: "Sales") }
    let!(:consulting) { create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt") }
    let(:account) { create(:account, :csv, business: business) }
    let!(:payout) { create(:transaction, account: account, payee: "STRIPE PAYOUT", amount_cents: 97_070, external_id: "x1") }

    before { sign_in_as user_with_role("editor", business) }

    it "saves a fee and tax on an imported deposit" do
      patch business_transaction_path(business, payout),
        params: { transaction: { category_id: sales.id, processor_fee: "29.30", sales_tax: "84.67" } }
      expect([ payout.reload.processor_fee_cents, payout.sales_tax_cents ]).to eq([ 2_930, 8_467 ])
    end

    it "computes tax-inclusive tax on the unallocated gross and returns to the form" do
      patch business_transaction_path(business, payout),
        params: { apply_inclusive_tax: "1", transaction: { category_id: sales.id, processor_fee: "29.30", sales_tax: "" } }
      expect(response).to redirect_to(edit_business_transaction_path(business, payout))
      expect(flash[:notice]).to eq("Sales tax set to $84.67 (tax-inclusive at 9.25%).")
      expect(payout.reload.sales_tax_cents).to eq(8_467)
    end

    [ [ "-5", "can't be negative" ], [ "abc", "is not a valid amount" ], [ "1,00", "is not a valid amount" ] ].each do |input, message|
      it "rejects a fee of #{input.inspect}" do
        patch business_transaction_path(business, payout), params: { transaction: { category_id: sales.id, processor_fee: input } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(ERB::Util.html_escape("Processor fee #{message}"))
      end
    end

    it "refuses tax on an exempt deposit" do
      patch business_transaction_path(business, payout), params: { transaction: { category_id: consulting.id, sales_tax: "5.00" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Clear the sales tax first.")
    end

    it "gives a manual remittance the default period and lets the editor pick another" do
      cash = create(:account, business: business, name: "Cash")
      remittance = business.categories.sales_tax_remittance.sole
      post business_transactions_path(business), params: { transaction: { account_id: cash.id, posted_on: "2026-04-10", payee: "TN DOR",
                                                                            amount: "84.67", direction: "out", category_id: remittance.id } }
      created = cash.transactions.sole
      expect(created.sales_tax_period_starts_on).to eq(Date.new(2026, 1, 1))
      patch business_transaction_path(business, created), params: { transaction: { sales_tax_period_starts_on: "2026-04-01" } }
      expect(created.reload.sales_tax_period_starts_on).to eq(Date.new(2026, 4, 1))
    end

    it "lists taxable deposits that still need tax" do
      payout.update!(category: sales)
      create(:transaction, account: account, payee: "STRIPE DONE", amount_cents: 10_925, category: sales, sales_tax_cents: 925)
      get business_transactions_path(business, status: "needs_tax")
      expect(response.body).to include("STRIPE PAYOUT")
      expect(response.body).not_to include("STRIPE DONE")
    end

    it "hides the fee field on the personal book" do
      household_owner = create(:user, :household_owner)
      book = PersonalBookProvisioner.call(Household.first)
      txn = create(:transaction, account: create(:account, business: book), amount_cents: 5_000)
      sign_in_as household_owner
      get edit_business_transaction_path(book, txn)
      expect(response.body).not_to include("Processor fee")
    end
  end
end
