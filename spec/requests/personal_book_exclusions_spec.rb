require "rails_helper"

RSpec.describe "Personal book exclusions" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:book) { PersonalBookProvisioner.call(household) }
  let!(:accountant) { user_with_role("viewer", business) }

  before do
    groceries = book.categories.find_by!(name: "Groceries")
    create(:transaction, account: create(:account, business: book), payee: "SECRET GROCER", amount_cents: -4_200,
                         posted_on: Date.current, category: groceries)
    create(:transaction, account: create(:account, business: business), payee: "OFFICE DEPOT", amount_cents: -1_000,
                         posted_on: Date.current, category: create(:category, business: business, name: "Office expense"))
  end

  it "keeps household access for the accountant, who has no personal membership" do
    expect(accountant.can_view_household?).to be(true)
  end

  it "404s every personal-book screen for the accountant" do
    sign_in_as accountant
    [ business_path(book), business_accounts_path(book), business_transactions_path(book), business_inbox_path(book),
      business_categories_path(book), business_rules_path(book) ].each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
    end
  end

  it "leaves personal rows out of household reports, exports, and the dashboard business list" do
    sign_in_as owner
    get household_profit_and_loss_path
    expect(response.body).to include("Pat Consulting", "Office expense")
    expect(response.body).not_to include("Groceries")
    get household_transaction_export_path
    expect(response.body).to include("OFFICE DEPOT")
    expect(response.body).not_to include("SECRET GROCER")
    get root_path
    expect(response.body.scan(%(href="#{business_path(book)}")).size).to eq(2) # site nav + Personal section, not the business list
  end

  it "shows the personal inbox group to members only" do
    Transaction.for_businesses(book.id).update_all(category_id: nil, categorized_by: nil)
    sign_in_as owner
    get household_inbox_path
    expect(response.body).to include("SECRET GROCER")
    sign_in_as accountant
    get household_inbox_path
    expect(response.body).not_to include("SECRET GROCER")
  end

  it "never grants the personal book through an invite" do
    sign_in_as owner
    get new_invite_path
    expect(response.body).not_to include("invite[grant_roles][#{book.id}]")
    expect {
      post invites_path, params: { invite: { grant_roles: { book.id.to_s => "viewer" } } }
    }.not_to change(Invite, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end
end
