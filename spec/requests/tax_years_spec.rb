require "rails_helper"

RSpec.describe "Taxes page" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }
  let!(:owner) { create(:user, :household_owner).tap { create(:membership, user: _1, business:, role: "owner") } }
  let!(:accountant) { user_with_role("viewer", business) }
  let(:personal) { create(:business, :personal, household:).tap { create(:membership, user: owner, business: _1, role: "owner") } }

  before do
    create(:tax_parameters, :federal_2026)
    income = create(:category, :income, business:)
    create(:transaction, account: create(:account, business:), category: income, posted_on: Date.new(2026, 2, 1), amount_cents: 2_500_000)
  end

  around { |example| travel_to(Date.new(2026, 5, 1)) { example.run } }

  it "redirects /taxes to the current year" do
    sign_in_as owner
    get tax_years_path
    expect(response).to redirect_to(tax_year_path(2026))
  end

  it "redirects /taxes to the previous year until its January installment is due" do
    travel_to Date.new(2027, 1, 10)
    sign_in_as owner
    get tax_years_path
    expect(response).to redirect_to(tax_year_path(2026))
  end

  it "shows pay at least, the due date, the IRS link, the worksheet, and the estimate note" do
    sign_in_as owner
    get tax_year_path(2026)
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("Estimated tax").and include("Pay at least").and include("Jun 15, 2026")
    expect(body).to include("This is an estimate. Verify with your accountant.")
    expect(body).to include("<details")
    link = Nokogiri::HTML(body).at_css("a[href='https://www.irs.gov/payments/direct-pay']")
    expect(link.text).to include("Pay on IRS.gov")
    expect(link["target"]).to eq("_blank")
    expect(link["rel"]).to eq("noopener noreferrer")
  end

  it "shows the year's progress but leaves the quarters to the installments table" do
    sign_in_as owner
    get tax_year_path(2026)
    card = Nokogiri::HTML(response.body).at_css(".tax-due")
    expect(card.at_css(".tax-due-progress").text).to include("required for 2026")
    expect(card.at_css(".tax-due-quarters")).to be_nil
  end

  it "shows the Home office and Adjustments links to the household owner but not the accountant" do
    pat = create(:person, household:, name: "Pat Example")
    business.update!(person: pat)
    links = [ edit_business_home_office_path(business, 2026), edit_person_adjustment_path(pat, 2026) ]
    sign_in_as owner
    get tax_year_path(2026)
    expect(response.body).to include(*links)
    delete session_path
    sign_in_as accountant
    get tax_year_path(2026)
    expect(response).to have_http_status(:ok)
    links.each { expect(response.body).not_to include(_1) }
  end

  it "uses the household's IRS URL" do
    household.update!(irs_payment_url: "https://www.irs.gov/payments")
    sign_in_as owner
    get tax_year_path(2026)
    expect(response.body).to include('href="https://www.irs.gov/payments"')
  end

  it "selects a quarter from the URL and ignores a bad one" do
    sign_in_as owner
    get tax_year_path(2026, quarter: 1)
    expect(response.body).to include("Worksheet for Q1")
    get tax_year_path(2026, quarter: 9)
    expect(response.body).to include("Worksheet for Q2")
  end

  it "asks for missing prior-year figures" do
    sign_in_as owner
    get tax_year_path(2026)
    expect(response.body).to include("Enter last year&#39;s total tax and AGI to use the safe harbor.")
  end

  it "renders a future year and a past year without parameters" do
    sign_in_as owner
    get tax_year_path(2027)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Federal tax figures for 2027 are incomplete.")
    get tax_year_path(2025)
    expect(response.body).to include("Federal tax figures for 2025 are incomplete.")
  end

  it "lists the household's businesses and people on the incomplete page" do
    pat = create(:person, household:, name: "Pat Example")
    sign_in_as owner
    get tax_year_path(2027)
    expect(response.body).to include("Inputs").and include(business.name).and include("Pat Example")
    expect(response.body).to include(edit_person_adjustment_path(pat, 2027))
    expect(response.body).to include(edit_business_home_office_path(business, 2027))
  end

  it "hides the home office link from a household owner who isn't a member of the book" do
    other = create(:business, household:)
    sign_in_as owner
    get tax_year_path(2027)
    expect(response.body).not_to include(edit_business_home_office_path(other, 2027))
  end

  it "treats mileage-only parameters as incomplete, with inputs and the payment log" do
    mileage_only = create(:tax_parameters, year: 2028)
    sign_in_as owner
    get tax_year_path(2028)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Federal tax figures for 2028 are incomplete.").and include("Inputs").and include("Payments")
    expect(Nokogiri::HTML(response.body).at_css("a[href='#{edit_tax_parameter_path(mileage_only)}']").text).to eq("Enter them")
  end

  it "renders a year that hasn't started when it has parameters" do
    create(:tax_parameters, :federal_2026, year: 2027)
    sign_in_as owner
    get tax_year_path(2027)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pay at least")
  end

  it "404s a malformed or out-of-range year" do
    sign_in_as owner
    %w[1999 2101 abc 010].each do |year|
      get "/taxes/#{year}"
      expect(response).to have_http_status(:not_found), year
    end
  end

  it "lets a viewer of every business read but not edit" do
    sign_in_as accountant
    get tax_year_path(2026)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(edit_tax_year_path(2026))
    get edit_tax_year_path(2026)
    expect(response).to have_http_status(:forbidden)
    patch tax_year_path(2026), params: { tax_year: { prior_year_total_tax: "1" } }
    expect(response).to have_http_status(:forbidden)
  end

  it "404s a user without household access" do
    other = create(:business, household:)
    sign_in_as user_with_role("owner", other)
    get tax_year_path(2026)
    expect(response).to have_http_status(:not_found)
  end

  it "saves prior-year figures, creating the tax year" do
    sign_in_as owner
    patch tax_year_path(2026), params: { tax_year: { prior_year_total_tax: "24,000", prior_year_agi: "118,000" } }
    expect(response).to redirect_to(tax_year_path(2026))
    expect(TaxYear.find_by!(year: 2026)).to have_attributes(prior_year_total_tax_cents: 2_400_000, prior_year_agi_cents: 11_800_000)
  end

  it "re-renders bad prior-year figures" do
    sign_in_as owner
    patch tax_year_path(2026), params: { tax_year: { prior_year_total_tax: "abc" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "shows a personal-book debit to its members but not to the accountant" do
    debit = create(:transaction, account: create(:account, business: personal, name: "Joint Checking"), posted_on: Date.new(2026, 4, 14),
                                 amount_cents: -450_000, payee: "IRS USATAXPYMT")
    create(:estimated_payment, tax_year: create(:tax_year, household:), quarter: 1, paid_on: debit.posted_on, amount_cents: 450_000, debit:)
    sign_in_as owner
    get tax_year_path(2026)
    expect(response.body).to include("IRS USATAXPYMT").and include("Joint Checking")
    delete session_path
    sign_in_as accountant
    get tax_year_path(2026)
    expect(response.body).to include("$4,500.00").and include("Linked to a bank transaction")
    expect(response.body).not_to include("IRS USATAXPYMT")
  end
end
