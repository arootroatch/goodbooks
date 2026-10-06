require "rails_helper"

RSpec.describe "Inbox" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:account) { create(:account, business: business) }
  let!(:category) { create(:category, business: business, name: "Software") }
  let!(:txn) { create(:transaction, account: account, payee: "ADOBE CREATIVE", amount_cents: -5499) }
  let!(:done) { create(:transaction, account: account, payee: "ALREADY DONE", category: category) }

  it "lists only inbox transactions" do
    sign_in_as user_with_role("viewer", business)
    get business_inbox_path(business)
    expect(response.body).to include("ADOBE CREATIVE")
    expect(response.body).not_to include("ALREADY DONE")
  end

  it "categorizes with a turbo stream that removes the row" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn),
      params: { outcome: "categorize", category_id: category.id }, as: :turbo_stream
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(action="remove" target="transaction_#{txn.id}"))
    expect(txn.reload.category).to eq(category)
    expect(txn.categorized_by).to eq("user")
  end

  it "marks transfer and exclude with HTML fallback" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn), params: { outcome: "transfer" }
    expect(response).to redirect_to(business_inbox_path(business))
    expect(txn.reload).to be_transfer
    other = create(:transaction, account: account)
    patch business_transaction_classification_path(business, other), params: { outcome: "exclude" }
    expect(other.reload).to be_excluded
  end

  it "asks for a category when none is chosen" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn), params: { outcome: "categorize", category_id: "" }
    expect(flash[:alert]).to eq("Choose a category.")
    expect(txn.reload).to be_inbox
  end

  it "jumps to a prefilled rule form when asked" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn),
      params: { outcome: "categorize", category_id: category.id, make_rule: "1" }, as: :turbo_stream
    expect(response).to redirect_to(new_business_rule_path(business, value: "ADOBE", category_id: category.id))
  end

  it "forbids viewers from classifying" do
    sign_in_as user_with_role("viewer", business)
    patch business_transaction_classification_path(business, txn), params: { outcome: "exclude" }
    expect(response).to have_http_status(:forbidden)
    expect(txn.reload).not_to be_excluded
  end

  it "rejects a category from another business" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn), params: { outcome: "categorize", category_id: create(:category).id }
    expect(flash[:alert]).to eq("Choose a category.")
  end

  describe "household inbox" do
    let!(:other_business) { create(:business, name: "Hidden Biz") }
    let!(:hidden) { create(:transaction, account: create(:account, business: other_business), payee: "SECRET PAYEE") }

    it "shows inbox rows from every accessible business only" do
      sign_in_as user_with_role("editor", business)
      get household_inbox_path
      expect(response.body).to include("ADOBE CREATIVE")
      expect(response.body).not_to include("SECRET PAYEE")
    end
  end
end
