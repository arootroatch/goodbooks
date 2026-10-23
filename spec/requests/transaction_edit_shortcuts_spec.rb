require "rails_helper"

RSpec.describe "Shortcuts on the transaction edit page" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business:) }
  let!(:txn) { create(:transaction, account:, payee: "ADOBE CREATIVE CLOUD 123") }
  let!(:software) { create(:category, business:, name: "Software") }

  before { sign_in_as user_with_role("editor", business) }

  def page = Capybara.string(response.body)

  it "links to a new category that comes back to this transaction with it selected" do
    get edit_business_transaction_path(business, txn)
    expect(page).to have_link("New category", href: new_business_category_path(business, transaction_id: txn.id))

    get new_business_category_path(business, transaction_id: txn.id)
    expect(page).to have_field("transaction_id", type: :hidden, with: txn.id.to_s)

    post business_categories_path(business), params: { transaction_id: txn.id,
                                                        category: { name: "Subscriptions", kind: "expense", schedule_c_line: "18" } }
    created = business.categories.find_by!(name: "Subscriptions")
    expect(response).to redirect_to(edit_business_transaction_path(business, txn, category_id: created.id))

    get edit_business_transaction_path(business, txn, category_id: created.id)
    expect(page.find("select[name='transaction[category_id]']")).to have_css("option[selected]", text: "Subscriptions")
  end

  it "ignores a transaction or category from another business" do
    other = create(:transaction)
    post business_categories_path(business), params: { transaction_id: other.id,
                                                        category: { name: "Elsewhere", kind: "expense", schedule_c_line: "18" } }
    expect(response).to redirect_to(business_categories_path(business))

    get edit_business_transaction_path(business, txn, category_id: create(:category).id)
    expect(page.find("select[name='transaction[category_id]']")).to have_no_css("option[selected]")
  end

  it "opens a rule pre-filled from the transaction when asked" do
    patch business_transaction_path(business, txn), params: { make_rule: "1", transaction: { category_id: software.id } }
    expect(txn.reload.category).to eq(software)
    expect(response).to redirect_to(new_business_rule_path(business, value: "ADOBE CREATIVE CLOUD 123", category_id: software.id))
  end

  it "offers the make-rule checkbox on the form" do
    get edit_business_transaction_path(business, txn)
    expect(page).to have_field("make_rule", type: :checkbox)
  end
end
