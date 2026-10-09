require "rails_helper"

RSpec.describe "Sales tax periods" do
  let!(:business) { create(:business) }
  let!(:profile) { create(:sales_tax_profile, business: business) }
  let(:account) { create(:account, business: business, name: "Checking") }
  let(:sales) { create(:category, :income, business: business, name: "Sales") }
  let(:q1) { Date.new(2026, 1, 1) }

  before do
    create(:transaction, account: account, category: sales, payee: "STRIPE PAYOUT", amount_cents: 97_070, processor_fee_cents: 2_930,
                         sales_tax_cents: 8_467, posted_on: Date.new(2026, 2, 6))
    create(:transaction, account: account, category: business.categories.sales_tax_remittance.sole, payee: "=TN DOR",
                         amount_cents: -8_467, posted_on: Date.new(2026, 4, 10), sales_tax_period_starts_on: q1)
  end

  it "shows the period's figures, deposits, and remittances to viewers, with a CSV" do
    sign_in_as user_with_role("viewer", business)
    get business_sales_tax_period_path(business, q1)
    expect(response.body).to include("Q1 2026", "$1,000.00", "$84.67", "STRIPE PAYOUT")
    expect(response.body).not_to include("Mark filed")
    get business_sales_tax_period_path(business, q1, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("'=TN DOR")
  end

  it "lets editors file and unfile, and forbids viewers" do
    sign_in_as user_with_role("viewer", business)
    post business_sales_tax_period_filing_path(business, q1), params: { sales_tax_filing: { filed_on: "2026-04-10" } }
    expect(response).to have_http_status(:forbidden)

    sign_in_as user_with_role("editor", business)
    post business_sales_tax_period_filing_path(business, q1), params: { sales_tax_filing: { filed_on: "2026-04-10", confirmation_number: "TN123" } }
    expect(response).to redirect_to(business_sales_tax_period_path(business, q1))
    follow_redirect!
    expect(response.body).to include("Paid", "TN123")
    post business_sales_tax_period_filing_path(business, q1), params: { sales_tax_filing: { filed_on: "2026-04-10" } }
    expect(flash[:alert]).to include("is already filed")
    delete business_sales_tax_period_filing_path(business, q1)
    expect(business.sales_tax_filings).to be_empty
  end

  it "rejects a blank filing date with a flash" do
    sign_in_as user_with_role("editor", business)
    post business_sales_tax_period_filing_path(business, q1), params: { sales_tax_filing: { filed_on: "" } }
    expect(flash[:alert]).to include("Filed on can't be blank")
  end

  {
    "a non-period-start date" => "2026-01-02",
    "a non-date" => "abc",
    "a date before the calendar" => "2025-10-01",
    "a future period start not yet in the calendar" => Date.current.next_year.beginning_of_year.iso8601,
    "the 2nd of a future month" => Date.current.next_month.beginning_of_month.next_day.iso8601
  }.each do |description, starts_on|
    it "is 404 for #{description}" do
      sign_in_as user_with_role("owner", business)
      get business_sales_tax_period_path(business, starts_on)
      expect(response).to have_http_status(:not_found)
      get business_sales_tax_period_path(business, starts_on, format: :csv)
      expect(response).to have_http_status(:not_found)
      post business_sales_tax_period_filing_path(business, starts_on), params: { sales_tax_filing: { filed_on: "2026-04-10" } }
      expect(response).to have_http_status(:not_found)
      delete business_sales_tax_period_filing_path(business, starts_on)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "is 404 while the profile is inactive and for non-members" do
    profile.update!(active: false)
    sign_in_as user_with_role("owner", business)
    get business_sales_tax_period_path(business, q1)
    expect(response).to have_http_status(:not_found)
    profile.update!(active: true)
    sign_in_as create(:user)
    get business_sales_tax_period_path(business, q1)
    expect(response).to have_http_status(:not_found)
  end

  it "is 404 on the personal book for the period page, its CSV, and filings" do
    household_owner = create(:user, :household_owner)
    book = PersonalBookProvisioner.call(Household.first)
    sign_in_as household_owner
    get business_sales_tax_period_path(book, q1)
    expect(response).to have_http_status(:not_found)
    get business_sales_tax_period_path(book, q1, format: :csv)
    expect(response).to have_http_status(:not_found)
    post business_sales_tax_period_filing_path(book, q1), params: { sales_tax_filing: { filed_on: "2026-04-10" } }
    expect(response).to have_http_status(:not_found)
    delete business_sales_tax_period_filing_path(book, q1)
    expect(response).to have_http_status(:not_found)
  end

  it "lets an editor move a remittance to another period from the period page" do
    q2 = Date.new(2026, 4, 1)
    remittance = Transaction.find_by!(payee: "=TN DOR")
    sign_in_as user_with_role("viewer", business)
    get business_sales_tax_period_path(business, q1)
    expect(response.body).not_to include("transaction[sales_tax_period_starts_on]")

    sign_in_as user_with_role("editor", business)
    get business_sales_tax_period_path(business, q1)
    expect(response.body).to include("transaction[sales_tax_period_starts_on]")
    patch business_transaction_path(business, remittance),
      params: { return_to_period: q1.iso8601, transaction: { sales_tax_period_starts_on: q2.iso8601 } }
    expect(response).to redirect_to(business_sales_tax_period_path(business, q1))
    expect(remittance.reload.sales_tax_period_starts_on).to eq(q2)
    get business_sales_tax_period_path(business, q2)
    expect(response.body).to include("$84.67")
    get business_sales_tax_period_path(business, q1)
    expect(response.body).not_to include("=TN DOR")
  end
end
