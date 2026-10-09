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
    expect(txn.reload).to be_inbox
    expect(txn.category).to be_nil
  end

  it "rejects an archived category" do
    sign_in_as user_with_role("editor", business)
    archived = create(:category, business: business, archived_at: Time.current)
    patch business_transaction_classification_path(business, txn), params: { outcome: "categorize", category_id: archived.id }
    expect(flash[:alert]).to eq("Choose a category.")
    expect(txn.reload).to be_inbox
    expect(txn.category).to be_nil
  end

  it "404s for a transaction from another business" do
    sign_in_as user_with_role("editor", business)
    other_txn = create(:transaction, account: create(:account, business: create(:business)))
    patch business_transaction_classification_path(business, other_txn), params: { outcome: "exclude" }
    expect(response).to have_http_status(:not_found)
    expect(other_txn.reload).not_to be_excluded
  end

  it "rejects an unknown outcome" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn), params: { outcome: "delete" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(txn.reload).to be_inbox
  end

  it "clears category and transfer when excluding" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, done), params: { outcome: "exclude" }
    expect(done.reload).to have_attributes(category: nil, transfer: false, excluded: true, categorized_by: "user")
  end

  it "categorizes with an HTML fallback" do
    sign_in_as user_with_role("editor", business)
    patch business_transaction_classification_path(business, txn), params: { outcome: "categorize", category_id: category.id }
    expect(response).to redirect_to(business_inbox_path(business))
    expect(txn.reload.category).to eq(category)
  end

  it "hides classification forms from viewers" do
    sign_in_as user_with_role("viewer", business)
    get business_inbox_path(business)
    expect(response.body).to include("ADOBE CREATIVE")
    expect(response.body).not_to include(%(name="outcome"))
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

  describe "length limit" do
    before do
      stub_const("InboxesController::LIMIT", 1)
      create(:transaction, account: account, payee: "SECOND ONE", posted_on: Date.new(2020, 1, 1))
    end

    it "truncates the business inbox and says so" do
      sign_in_as user_with_role("viewer", business)
      get business_inbox_path(business)
      expect(response.body).to include("Showing 1 of 2")
      expect(response.body.scan("<tr id=").size).to eq(1)
    end

    it "truncates each business in the household inbox" do
      sign_in_as create(:user, :household_owner).tap { |u| create(:membership, user: u, business: business, role: "owner") }
      get household_inbox_path
      expect(response.body).to include("Showing 1 of 2")
    end
  end

  it "refuses to reclassify a taxed deposit through the inbox endpoint" do
    business = create(:business)
    create(:sales_tax_profile, business: business)
    sales = create(:category, :income, business: business, name: "Sales")
    exempt = create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt")
    taxed = create(:transaction, account: create(:account, business: business), amount_cents: 10_925, category: sales, sales_tax_cents: 925)
    sign_in_as user_with_role("editor", business)
    [ { outcome: "transfer" }, { outcome: "exclude" }, { outcome: "categorize", category_id: exempt.id } ].each do |params|
      patch business_transaction_classification_path(business, taxed), params: params
      expect(flash[:alert]).to include("Clear the sales tax first.")
    end
    expect([ taxed.reload.transfer, taxed.excluded, taxed.category_id ]).to eq([ false, false, sales.id ])
  end

  it "offers the remittance category in the inbox picker" do
    business = create(:business)
    create(:sales_tax_profile, business: business)
    create(:transaction, account: create(:account, business: business), payee: "TN DOR", amount_cents: -100)
    sign_in_as user_with_role("editor", business)
    get business_inbox_path(business)
    expect(response.body).to include('label="Sales tax"', "Sales tax remittance")
  end
end
