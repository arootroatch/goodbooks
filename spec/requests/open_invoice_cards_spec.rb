require "rails_helper"

RSpec.describe "Open invoice cards" do
  let!(:business) { create(:business, name: "Sound Roots") }
  let(:globex) { create(:client, business:, name: "Globex") }
  let(:acme) { create(:client, business:, name: "Acme") }

  before do
    create(:invoice, business:, client: globex, number: "INV-1", amount_cents: 120_000, due_date: Date.current - 45)
    create(:invoice, business:, client: acme, number: "INV-2", amount_cents: 200_000, due_date: Date.current + 5)
    create(:invoice, business:, client: acme, number: "INV-3", amount_cents: 90_000, due_date: Date.current - 10, status: "paid")
  end

  def cards = Capybara.string(response.body).find(".open-invoices")

  it "shows overdue and not-yet-due invoices above the business invoice table, without the old summary line" do
    sign_in_as user_with_role("viewer", business)
    get business_invoices_path(business)
    overdue = cards.find(".open-invoices-overdue")
    expect(overdue).to have_css(".card-title", text: "Overdue invoices").and have_css(".card-title", text: "$1,200.00 · 1")
    expect(overdue).to have_link("INV-1", href: business_invoice_path(business, Invoice.find_by!(number: "INV-1")))
    expect(overdue).to have_text("Globex").and have_text("45 days late")
    upcoming = cards.find(".open-invoices-upcoming")
    expect(upcoming).to have_css(".card-title", text: "Outstanding invoices").and have_css(".card-title", text: "$2,000.00 · 1")
    expect(upcoming).to have_text("Acme").and have_text("due in 5 days")
    expect(cards).to have_no_text("INV-3")
    expect(response.body).not_to include("Outstanding $")
    header = Capybara.string(response.body).find("main header.page-header")
    expect(header).to have_link("Aging", href: business_invoice_aging_path(business), class: "button")
    expect(header).to have_link("Download CSV", class: "button")
  end

  it "lists five per card and links the rest to the filtered table" do
    5.times { |i| create(:invoice, business:, client: globex, number: "LATE-#{i}", due_date: Date.current - 2 - i) }
    sign_in_as user_with_role("viewer", business)
    get business_invoices_path(business)
    overdue = cards.find(".open-invoices-overdue")
    expect(overdue).to have_css("li", count: 5)
    expect(overdue).to have_link("and 1 more", href: business_invoices_path(business, status: "overdue"))
  end

  it "says when nothing is overdue" do
    Invoice.find_by!(number: "INV-1").update!(due_date: Date.current)
    sign_in_as user_with_role("viewer", business)
    get business_invoices_path(business)
    expect(cards.find(".open-invoices-overdue")).to have_text("Nothing overdue.")
    expect(cards.find(".open-invoices-upcoming")).to have_text("due today")
  end

  it "shows the cards with business names on the household invoices page" do
    sign_in_as create(:user, :household_owner)
    get household_invoices_path
    expect(cards.find(".open-invoices-overdue")).to have_text("Sound Roots")
    expect(response.body).not_to include("Outstanding $")
  end

  it "shows the cards on the business overview instead of the receivables subtitle" do
    sign_in_as user_with_role("viewer", business)
    get business_path(business)
    expect(cards.find(".open-invoices-overdue")).to have_text("INV-1")
    expect(Capybara.string(response.body).find(".page-header .subtitle")).to have_no_text("Outstanding")
  end
end
