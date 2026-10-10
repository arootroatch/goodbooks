require "rails_helper"

RSpec.describe "Navigation" do
  let!(:household) { create(:household) }
  let!(:person) { create(:person, household: household) }
  let(:household_owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, person: person, name: "Studio LLC"), owner: household_owner) }

  def sidebar = Capybara.string(response.body).find("nav.sidebar")

  it "shows the business section with every business page on a business page" do
    sign_in_as household_owner
    get business_transactions_path(business)
    expect(sidebar).to have_link("Overview", href: business_path(business))
    expect(sidebar).to have_link("Inbox", href: business_inbox_path(business))
    expect(sidebar).to have_link("Transactions", href: business_transactions_path(business))
    expect(sidebar).to have_link("Accounts", href: business_accounts_path(business))
    expect(sidebar).to have_link("Categories", href: business_categories_path(business))
    expect(sidebar).to have_link("Rules", href: business_rules_path(business))
    expect(sidebar).to have_link("Mileage", href: business_mileage_entries_path(business))
    expect(sidebar).to have_link("Members", href: business_memberships_path(business))
    expect(sidebar).to have_link("Profit & loss", href: business_profit_and_loss_path(business))
    expect(sidebar).to have_link("Schedule C", href: business_schedule_c_path(business))
  end

  it "hides owner-only links from viewers" do
    sign_in_as user_with_role("viewer", business)
    get business_transactions_path(business)
    expect(sidebar).to have_no_link("Members")
    expect(sidebar).to have_no_link("Tax parameters")
    expect(sidebar).to have_no_link("People")
    expect(sidebar).to have_no_link("Invites")
  end

  it "shows household owner links" do
    sign_in_as household_owner
    get root_path
    expect(sidebar).to have_link("All businesses", href: root_path)
    expect(sidebar).to have_link("Household inbox", href: household_inbox_path)
    expect(sidebar).to have_link("Household P&L", href: household_profit_and_loss_path)
    expect(sidebar).to have_link("Tax parameters", href: tax_parameters_path)
    expect(sidebar).to have_link("Invites", href: invites_path)
    expect(sidebar).to have_link("People", href: people_path)
  end

  it "omits the business section outside a business" do
    sign_in_as household_owner
    get root_path
    expect(sidebar).to have_no_link("Overview")
    expect(sidebar).to have_no_css(".nav-group", text: "Reports")
  end

  it "offers the household as the first switcher option" do
    sign_in_as household_owner
    get business_transactions_path(business)
    expect(sidebar.first(".switcher li a", visible: :all)).to have_text("Household")
    expect(sidebar).to have_css(".switcher li a[href='#{root_path}']", text: "Household", visible: :all)
  end

  it "labels the switcher with one of its own options" do
    sign_in_as household_owner
    { root_path => "Household", business_transactions_path(business) => "Studio LLC" }.each do |path, label|
      get path
      expect(sidebar.find(".switcher summary").text).to eq(label)
      expect(sidebar.all(".switcher li a", visible: :all).map(&:text)).to include(label)
    end
  end

  it "hides household links inside a business" do
    sign_in_as household_owner
    get business_transactions_path(business)
    expect(sidebar).to have_no_link("All businesses")
    expect(sidebar).to have_no_link("Household inbox")
    expect(sidebar).to have_no_link("Household P&L")
    expect(sidebar).to have_no_css(".nav-group", text: "Household")
  end

  it "puts the app-wide section above the context links in every menu" do
    sign_in_as household_owner
    [ root_path, business_transactions_path(business) ].each do |path|
      get path
      groups = sidebar.all(".nav-group").map(&:text)
      expect(groups.first).to eq("Settings")
      links = sidebar.all("a").map(&:text)
      expect(links.index("People")).to be < links.index(path == root_path ? "All businesses" : "Overview")
    end
  end

  it "omits the app-wide heading when the user has none of its links" do
    sign_in_as user_with_role("viewer", business)
    get business_transactions_path(business)
    expect(sidebar).to have_no_css(".nav-group", text: "Settings")
  end

  it "renders for a user with no memberships" do
    sign_in_as create(:user)
    get root_path
    expect(response).to have_http_status(:ok)
    expect(sidebar).to have_no_link("Overview")
    expect(sidebar).to have_no_link("Household P&L")
    expect(sidebar.all(".switcher li", visible: :all).map(&:text)).to eq([ "Household" ])
  end

  it "lists accessible businesses in the switcher" do
    other = create(:business, name: "Hidden Co")
    sign_in_as user_with_role("viewer", business)
    get business_transactions_path(business)
    expect(sidebar).to have_css(".switcher li a", text: "Studio LLC", visible: :all)
    expect(sidebar).to have_no_text(other.name)
  end

  it "badges the inbox with the uncategorized count" do
    account = create(:account, business: business)
    create_list(:transaction, 2, account: account, category: nil)
    sign_in_as household_owner
    get business_transactions_path(business)
    expect(sidebar.find_link("Inbox", href: business_inbox_path(business))).to have_css(".badge", text: "2")
  end

  it "marks the current page" do
    sign_in_as household_owner
    get business_rules_path(business)
    expect(sidebar).to have_css('a[aria-current="page"]', text: "Rules")
  end

  it "renders signed-out pages in the auth card without a sidebar" do
    get new_session_path
    page = Capybara.string(response.body)
    expect(page).to have_no_css("nav.sidebar")
    expect(page).to have_css(".auth-card form")
  end

  it "no longer renders the in-page business nav" do
    sign_in_as household_owner
    get business_transactions_path(business)
    expect(response.body).not_to include("business-nav")
  end
end
