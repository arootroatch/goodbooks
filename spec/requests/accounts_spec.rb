require "rails_helper"

RSpec.describe "Accounts" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business, name: "Checking") }

  it "lists accounts for viewers" do
    sign_in_as user_with_role("viewer", business)
    get business_accounts_path(business)
    expect(response.body).to include("Checking")
  end

  it "lets owners create a CSV account" do
    sign_in_as user_with_role("owner", business)
    post business_accounts_path(business), params: { account: { name: "Card", source: "csv", kind: "credit" } }
    expect(response).to redirect_to(business_accounts_path(business))
    expect(business.accounts.find_by!(name: "Card")).to be_csv
  end

  it "does not allow creating Plaid accounts by hand" do
    sign_in_as user_with_role("owner", business)
    post business_accounts_path(business), params: { account: { name: "Sneaky", source: "plaid", kind: "checking" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "forbids editors and viewers from changing accounts" do
    %w[editor viewer].each do |role|
      sign_in_as user_with_role(role, business)
      post business_accounts_path(business), params: { account: { name: "X", source: "manual", kind: "cash" } }
      expect(response).to have_http_status(:forbidden)
      patch business_account_path(business, account), params: { account: { name: "Y" } }
      expect(response).to have_http_status(:forbidden)
      delete session_path
    end
  end

  it "is not found for non-members and for another business's account" do
    other_account = create(:account)
    sign_in_as user_with_role("owner", business)
    get edit_business_account_path(business, other_account)
    expect(response).to have_http_status(:not_found)
    delete session_path
    sign_in_as create(:user)
    get business_accounts_path(business)
    expect(response).to have_http_status(:not_found)
  end

  it "hides archived accounts by default" do
    archived_account = create(:account, business: business, name: "Savings", archived_at: 1.day.ago)
    sign_in_as user_with_role("viewer", business)
    get business_accounts_path(business)
    expect(response.body).to include("Checking")
    expect(response.body).not_to include("Savings")
  end

  it "shows archived accounts with archived=1" do
    archived_account = create(:account, business: business, name: "Savings", archived_at: 1.day.ago)
    sign_in_as user_with_role("viewer", business)
    get business_accounts_path(business, archived: "1")
    expect(response.body).to include("Checking")
    expect(response.body).to include("Savings")
  end

  describe "balances" do
    let!(:book) { create(:business) }

    it "lets the owner set an opening balance on a manual account and shows the balance" do
      account = create(:account, business: book, name: "Savings", kind: "savings")
      sign_in_as user_with_role("owner", book)
      patch business_account_path(book, account), params: { account: { name: "Savings", kind: "savings",
                                                                        opening_balance: "8,000.00", opening_balance_on: "2026-01-01" } }
      expect(account.reload).to have_attributes(opening_balance_cents: 8_000_00, opening_balance_on: Date.new(2026, 1, 1))
      get business_accounts_path(book)
      expect(Nokogiri::HTML(response.body).at_css("##{ActionView::RecordIdentifier.dom_id(account)} td.balance").text).to include("$8,000.00")
    end

    it "does not accept an opening balance for a Plaid account and shows its reported balance read-only" do
      account = create(:account, :plaid, business: book, reported_balance_cents: 12_34, balance_reported_at: 1.hour.ago)
      sign_in_as user_with_role("owner", book)
      patch business_account_path(book, account), params: { account: { name: account.name, kind: "checking",
                                                                        opening_balance: "5", opening_balance_on: "2026-01-01" } }
      expect(account.reload.opening_balance_cents).to be_nil
      get edit_business_account_path(book, account)
      expect(response.body).to include("$12.34").and include("reported about 1 hour ago")
      expect(response.body).not_to include("account[opening_balance]")
    end
  end

  describe "tithe" do
    let!(:owner) { create(:user, :household_owner) }
    let!(:book) { PersonalBookProvisioner.call(Household.first) }

    it "lets the owner mark a personal-book account as not counting toward the tithe" do
      savings = create(:account, business: book, name: "Savings", kind: "savings")
      sign_in_as owner
      get edit_business_account_path(book, savings)
      expect(Capybara.string(response.body)).to have_checked_field("Count income toward tithe")
      patch business_account_path(book, savings), params: { account: { name: "Savings", kind: "savings", tithable: "0" } }
      expect(savings.reload.tithable).to be(false)
      get business_accounts_path(book)
      expect(Capybara.string(response.body).find("##{ActionView::RecordIdentifier.dom_id(savings)} td.tithe")).to have_text("Not counted")

      post business_accounts_path(book), params: { account: { name: "Cash jar", source: "manual", kind: "cash", tithable: "0" } }
      expect(book.accounts.find_by!(name: "Cash jar").tithable).to be(false)
    end

    it "leaves the tithe setting off business books" do
      sign_in_as user_with_role("owner", business)
      get edit_business_account_path(business, account)
      expect(response.body).not_to include("account[tithable]")
      get business_accounts_path(business)
      expect(Capybara.string(response.body)).to have_no_css("th", text: "Tithe").and have_no_css("td.tithe")
    end
  end
end
