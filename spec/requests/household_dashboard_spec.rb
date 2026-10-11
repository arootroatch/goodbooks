require "rails_helper"

RSpec.describe "Household dashboard" do
  let!(:household) { create(:household) }
  let(:owner) { create(:user, :household_owner) }
  let(:person) { create(:person, household:) }
  let!(:studio) { BusinessProvisioner.call(build(:business, person:, name: "Studio"), owner:) }

  def page = Capybara.string(response.body)
  def kpi(label) = page.find(".kpi", text: label)

  before do
    create(:transaction, account: studio.accounts.first, category: studio.categories.find_by!(kind: "income"),
                         amount_cents: 500_000, posted_on: Date.current.beginning_of_year)
    create(:transaction, account: studio.accounts.first, amount_cents: -2_000, posted_on: Date.current)
    create(:invoice, business: studio, number: "INV-9", amount_cents: 120_000, due_date: Date.current - 5)
  end

  it "shows invoices, businesses, the inbox, and the personal book at a glance" do
    book = PersonalBookProvisioner.call(household)
    book.update!(tithe_start_on: Date.current - 14)
    sign_in_as owner
    get root_path

    expect(page.find("main header.page-header h1")).to have_text("Household")
    expect(page.first(".kpis").all(".kpi small").map(&:text)).to eq([ "Overdue", "Outstanding", "Business net #{Date.current.year}", "Tithe" ])
    expect(kpi("Overdue")).to have_css("b.neg", text: "$1,200.00").and have_text("1 invoice")
    expect(kpi("Tithe")).to have_text("Even")
    expect(page.find(".open-invoices-overdue")).to have_text("INV-9").and have_text("Studio")

    card = page.find(".business-card", text: "Studio")
    expect(card).to have_link("Studio", href: business_path(studio))
    expect(card).to have_text("$5,000.00").and have_text("Overdue $1,200.00")
    expect(card).to have_link("1 to categorize", href: business_inbox_path(studio))

    expect(page.find(".inbox-summary")).to have_link("1 transaction to categorize", href: household_inbox_path)

    personal = page.find(".personal-summary")
    expect(personal).to have_link("Personal", href: business_path(book))
    expect(personal.all(".kpi small").map(&:text)).to eq([ "Income", "Spending", "Net" ])
    tithe = page.find(".tithe-summary")
    expect(tithe.find(".summary-card-header")).to have_css("h2", text: "Tithe")
    expect(tithe.find(".summary-card-header")).to have_link("Tithe details", href: business_tithe_path(book))
  end

  it "offers to set up the personal book to the household owner" do
    sign_in_as owner
    get root_path
    expect(page).to have_button("Set up personal book")
    expect(page).to have_no_css(".personal-summary")
  end

  it "leaves the personal book out for the accountant" do
    PersonalBookProvisioner.call(household).update!(tithe_start_on: Date.current - 14)
    accountant = create(:user)
    create(:membership, user: accountant, business: studio, role: "viewer")
    sign_in_as accountant
    get root_path
    expect(page.first(".kpis").all(".kpi small").map(&:text)).not_to include("Tithe")
    expect(page).to have_no_css(".personal-summary, .tithe-summary")
    expect(page).to have_no_button("Set up personal book")
    expect(page).to have_css(".business-card", text: "Studio")
  end

  it "says when the inbox is empty" do
    Transaction.update_all(excluded: true)
    sign_in_as owner
    get root_path
    expect(page.find(".inbox-summary")).to have_text("Inbox zero")
  end
end
