require "rails_helper"

RSpec.describe "Linked deposit guards" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business) }
  let!(:income) { create(:category, :income, business: business) }
  let!(:invoice) { create(:invoice, business: business, number: "INV-7") }
  let!(:deposit) { create(:transaction, account: account, amount_cents: invoice.amount_cents, category: income, categorized_by: "user") }

  before do
    create(:invoice_payment, invoice: invoice, deposit: deposit)
    sign_in_as user_with_role("editor", business)
  end

  it "refuses to delete a linked manual deposit" do
    delete business_transaction_path(business, deposit)
    expect(response).to redirect_to(edit_business_transaction_path(business, deposit))
    expect(flash[:alert]).to eq("Linked to INV-7 — unlink the payment first.")
    expect(Transaction.exists?(deposit.id)).to be(true)
  end

  it "refuses crafted classification changes" do
    %w[transfer exclude].each do |outcome|
      patch business_transaction_classification_path(business, deposit), params: { outcome: outcome }
      expect(flash[:alert]).to eq("Linked to INV-7 — unlink the payment first.")
    end
    expect(deposit.reload.category).to eq(income)
    expect(deposit).not_to be_transfer
    expect(deposit).not_to be_excluded
  end

  it "re-renders the edit form when recategorized to an expense" do
    patch business_transaction_path(business, deposit), params: { transaction: { category_id: create(:category, business: business).id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Linked to INV-7 — unlink the payment first.")
  end
end
