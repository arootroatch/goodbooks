require "rails_helper"

RSpec.describe "Transaction list filters" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business) }
  let!(:mine) { create(:transaction, account: account, payee: "My own payee") }
  let!(:other_account) { create(:account) }
  let!(:theirs) { create(:transaction, account: other_account, payee: "Other business payee") }

  before { sign_in_as user_with_role("viewer", business) }

  it "never shows another business's transactions when filtering by its account" do
    get business_transactions_path(business, account_id: other_account.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Other business payee")
    expect(response.body).not_to include("My own payee")
  end

  it "groups the category filter into Income and Expense, keeping the selection" do
    sales = create(:category, :income, business:, name: "Sales")
    create(:category, business:, name: "Supplies")
    get business_transactions_path(business, category_id: sales.id)
    select = Capybara.string(response.body).find("select[name=category_id]")
    expect(select.all("optgroup").map { _1[:label] }).to eq(%w[Income Expense])
    expect(select.find("optgroup[label=Income]")).to have_css("option[selected]", text: "Sales")
    expect(select.find("optgroup[label=Expense]")).to have_css("option", text: "Supplies")
    expect(select).to have_css("option[value='']", text: "All categories")
  end

  it "ignores non-scalar filter values" do
    get business_transactions_path(business, account_id: [ account.id ], q: { "x" => "y" })
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("My own payee")
  end

  it "still filters by its own account" do
    get business_transactions_path(business, account_id: account.id)
    expect(response.body).to include("My own payee")
  end
end
