require "rails_helper"

RSpec.describe "Sales tax on the dashboard" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let(:account) { create(:account, business: business) }

  def seed_q1_sale
    create(:sales_tax_profile, business: business)
    sales = create(:category, :income, business: business, name: "Sales")
    create(:transaction, account: account, category: sales, amount_cents: 10_925, sales_tax_cents: 925, posted_on: Date.new(2026, 2, 3))
  end

  def expect_sales_tax_card(page)
    card = page.find(".sales-tax-summary")
    expect(card.find(".summary-card-header")).to have_css("h2", text: "Sales tax")
    next_filing = card.find(".sales-tax-next")
    expect(next_filing).to have_css(".card-title", text: "Next filing").and have_text("Q2 2026")
    expect(next_filing).to have_text("Due Jul 20, 2026").and have_text("due in 80 days")
    expect(card.find(".sales-tax-collected")).to have_css(".card-title", text: "Collected Q2 2026").and have_css("b", text: "$0.00")
    expect(card.find(".sales-tax-remitted")).to have_css(".card-title", text: "Remitted Q2 2026").and have_css("b", text: "$0.00")
    expect(card.all(:xpath, "./*[not(self::header)]").map { _1[:class].split.last })
      .to eq(%w[sales-tax-next sales-tax-collected sales-tax-remitted sales-tax-owed])
    owed = card.find(".sales-tax-owed")
    expect(owed).to have_css(".card-title", text: "Owed").and have_css("b", text: "$9.25")
    expect(owed).to have_css(".neg", text: "1 period overdue")
    card
  end

  it "shows a sales tax card on the business overview, the sales tax page, and the household page" do
    travel_to Date.new(2026, 5, 1) do
      seed_q1_sale
      sign_in_as user_with_role("viewer", business)

      get business_path(business)
      page = Capybara.string(response.body)
      expect(page.find("header.page-header")).to have_no_text("Sales tax")
      card = expect_sales_tax_card(page)
      expect(card).to have_link("Sales tax details", href: business_sales_tax_profile_path(business))
      expect(response.body).to include("isn't filed")

      get business_sales_tax_profile_path(business)
      card = expect_sales_tax_card(Capybara.string(response.body))
      expect(card).to have_no_link("Sales tax details")

      get root_path
      page = Capybara.string(response.body)
      card = expect_sales_tax_card(page)
      expect(card.find(".summary-card-header")).to have_text("Pat Consulting")
      expect(page.find(".business-card")).to have_no_text("Sales tax")
      expect(response.body).to include("Sales tax for Pat Consulting", "Q1 2026", "isn't filed")
    end
  end

  it "says nothing is overdue once past periods are filed and paid" do
    travel_to Date.new(2026, 5, 1) do
      seed_q1_sale
      create(:sales_tax_filing, business: business, period_starts_on: Date.new(2026, 1, 1))
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      owed = Capybara.string(response.body).find(".sales-tax-summary .sales-tax-owed")
      expect(owed).to have_text("Nothing overdue")
    end
  end

  it "shows nothing for businesses without sales tax" do
    sign_in_as user_with_role("owner", business)
    get root_path
    expect(Capybara.string(response.body)).to have_no_css(".sales-tax-summary")
    get business_path(business)
    expect(Capybara.string(response.body)).to have_no_css(".sales-tax-summary")
  end
end
