require "rails_helper"

RSpec.describe "Estimated tax on the dashboard" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }
  let!(:owner) { create(:user, :household_owner).tap { create(:membership, user: _1, business:, role: "owner") } }

  around { |example| travel_to(Date.new(2026, 5, 1)) { example.run } }

  it "shows the next installment with the IRS link and a link to the taxes page" do
    create(:tax_parameters, :federal_2026)
    sign_in_as owner
    get root_path
    card = Nokogiri::HTML(response.body).at_css(".tax-due")
    expect(card.at_css("h2").text).to include("Next estimated tax")
    expect(card.text).to include("Pay at least").and include("Jun 15, 2026")
    expect(card.at_css("a[target='_blank']")["href"]).to eq(Household::DEFAULT_IRS_PAYMENT_URL)
    expect(card.at_css("a[href='#{tax_year_path(2026)}']")).to be_present
  end

  it "shows the year's progress and every quarter" do
    create(:tax_parameters, :federal_2026)
    income = create(:category, :income, business:)
    create(:transaction, account: create(:account, business:), category: income, posted_on: Date.new(2026, 2, 1), amount_cents: 2_500_000)
    create(:estimated_payment, tax_year: create(:tax_year, household:, year: 2026), paid_on: Date.new(2026, 4, 15), amount_cents: 100_000)
    estimate = Tax.estimate(household: Household.instance, year: 2026)
    sign_in_as owner
    get root_path
    card = Nokogiri::HTML(response.body).at_css(".tax-due")
    expect(card.at_css(".tax-due-progress").text.squish)
      .to include("Paid $1,000.00 of #{ApplicationController.helpers.money(estimate.required_annual_cents)} required for 2026")
      .and include("#{estimate.paid_percent}%")
    expect(card.at_css(".goal-fill")["style"]).to eq("width: #{estimate.paid_percent}%")
    rows = card.css(".tax-due-quarters li")
    expect(rows.map { _1.at_css(".tax-due-quarter").text }).to eq(%w[Q1 Q2 Q3 Q4])
    expect(rows[0].text).to include("Apr 15").and include("Paid $1,000.00")
    expect(rows[1]["aria-current"]).to eq("true")
    expect(rows[0]["class"].to_s.include?("neg")).to eq(estimate.installments[0].pay_at_least_cents.positive?)
  end

  it "shows last year's Q4 installment in January" do
    create(:tax_parameters, :federal_2026)
    travel_to Date.new(2027, 1, 10)
    sign_in_as owner
    get root_path
    card = Nokogiri::HTML(response.body).at_css(".tax-due")
    expect(card.text).to include("Jan 15, 2027")
    expect(card.at_css("a[href='#{tax_year_path(2026)}']")).to be_present
  end

  it "is hidden when the year's federal figures are incomplete" do
    create(:tax_parameters)
    sign_in_as owner
    get root_path
    expect(response.body).not_to include("tax-due")
  end

  it "is hidden from a user without household access" do
    create(:tax_parameters, :federal_2026)
    other = create(:business, household:)
    sign_in_as user_with_role("owner", other)
    get root_path
    expect(response.body).not_to include("tax-due")
  end
end
