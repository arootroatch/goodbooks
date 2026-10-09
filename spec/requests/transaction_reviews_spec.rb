require "rails_helper"

RSpec.describe "Transactions needing review" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:account) { create(:account, :plaid, business: business, name: "Operating") }
  let!(:category) { create(:category, business: business, name: "Office expense") }
  let!(:flagged) do
    create(:transaction, account: account, payee: "USPS", plaid_transaction_id: "p-1", category: category, categorized_by: "user",
                         review_reason: "removed_by_bank")
  end

  it "lists flagged rows above the inbox, with the reason, in the business and household inboxes" do
    sign_in_as user_with_role("viewer", business)
    get business_inbox_path(business)
    expect(response.body).to include("Needs review (1)", "USPS", "Removed by the bank", "Office expense")
    expect(response.body).not_to include(business_transaction_review_path(business, flagged))
    get household_inbox_path
    expect(response.body).to include("Needs review (1)", "Removed by the bank")
  end

  it "keeps a row with a turbo stream that removes it from the list" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_review_path(business, flagged), params: { decision: "keep" }, as: :turbo_stream
    expect(response.body).to include(%(action="remove" target="review_transaction_#{flagged.id}"))
    expect(flagged.reload).to have_attributes(review_reason: nil, excluded: false)
  end

  it "excludes a row (HTML fallback redirects back)" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_review_path(business, flagged), params: { decision: "exclude" }
    expect(response).to redirect_to(business_inbox_path(business))
    expect(flagged.reload).to have_attributes(review_reason: nil, excluded: true)
  end

  it "won't exclude a deposit linked to an invoice" do
    income = create(:category, :income, business: business)
    flagged.update!(amount_cents: 120_000, category: income)
    InvoicePayments.link(invoice: create(:invoice, business: business, amount_cents: 120_000, number: "INV-1042"), deposit: flagged)
    sign_in_as user_with_role("editor", business)
    patch business_transaction_review_path(business, flagged), params: { decision: "exclude" }
    expect(flash[:alert]).to include("Linked to INV-1042")
    expect(flagged.reload).to have_attributes(review_reason: "removed_by_bank", excluded: false)
  end

  it "enforces access and input" do
    sign_in_as user_with_role("viewer", business)
    patch business_transaction_review_path(business, flagged), params: { decision: "keep" }
    expect(response).to have_http_status(:forbidden)

    sign_in_as user_with_role("editor", business)
    patch business_transaction_review_path(business, flagged), params: { decision: "delete" }
    expect(response).to have_http_status(:unprocessable_content)
    unflagged = create(:transaction, account: account)
    patch business_transaction_review_path(business, unflagged), params: { decision: "keep" }
    expect(response).to have_http_status(:not_found)

    sign_in_as user_with_role("editor", create(:business))
    patch business_transaction_review_path(business, flagged), params: { decision: "keep" }
    expect(response).to have_http_status(:not_found)
  end

  it "filters the transaction list to rows needing review" do
    create(:transaction, account: account, payee: "UNFLAGGED")
    sign_in_as user_with_role("viewer", business)
    get business_transactions_path(business, status: "review")
    expect(response.body).to include("USPS", "Needs review")
    expect(response.body).not_to include("UNFLAGGED")
  end

  it "counts rows needing review per book on the dashboard" do
    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(response.body).to include("Needs review", "Pat Consulting: 1 transaction")
  end
end
