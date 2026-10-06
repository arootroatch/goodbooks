require "rails_helper"

RSpec.describe "Reports" do
  let!(:household) { create(:household) }
  let!(:pat) { create(:business, name: "Pat Consulting") }
  let!(:jordan) { create(:business, name: "Jordan Studio") }
  let!(:sales) { create(:category, :income, business: pat, name: "Sales") }
  let!(:account) { create(:account, business: pat) }
  let!(:rate) { create(:tax_parameters, year: 2026, standard_mileage_rate_tenth_cents: 725) }

  before do
    create(:transaction, account: account, category: sales, amount_cents: 1_234_500, posted_on: Date.new(2026, 3, 1))
    create(:mileage_entry, business: pat, miles_tenths: 1234, driven_on: Date.new(2026, 3, 2))
  end

  let(:accountant) do
    create(:user).tap do |u|
      create(:membership, user: u, business: pat, role: "viewer")
      create(:membership, user: u, business: jordan, role: "viewer")
    end
  end

  it "shows a business P&L for a date range" do
    sign_in_as accountant
    get business_profit_and_loss_path(pat, from: "2026-01-01", to: "2026-12-31")
    expect(response.body).to include("$12,345.00")
    expect(response.body).to include("$89.47")
  end

  it "shows Schedule C with mileage on line 9" do
    sign_in_as accountant
    get business_schedule_c_path(pat, year: 2026)
    expect(response.body).to include("Line 9: Car and truck expenses")
    expect(response.body).to include("$12,255.53")
  end

  it "exports the mileage log and transactions as CSV" do
    sign_in_as accountant
    get business_mileage_log_path(pat, year: 2026, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("123.4")
    get business_transaction_export_path(pat, from: "2026-01-01", to: "2026-12-31", format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(CSV.parse(response.body).size).to eq(2)
  end

  it "shows the household P&L to someone who can see every business" do
    sign_in_as accountant
    get household_profit_and_loss_path(from: "2026-01-01", to: "2026-12-31")
    expect(response.body).to include("Pat Consulting")
    expect(response.body).to include("Jordan Studio")
    get household_transaction_export_path(format: :csv, from: "2026-01-01", to: "2026-12-31")
    expect(response).to have_http_status(:ok)
  end

  it "hides household reports from someone missing a business" do
    sign_in_as user_with_role("owner", pat)
    get household_profit_and_loss_path
    expect(response).to have_http_status(:not_found)
    get household_transaction_export_path(format: :csv)
    expect(response).to have_http_status(:not_found)
  end

  it "is not found for non-members" do
    sign_in_as user_with_role("owner", jordan)
    get business_profit_and_loss_path(pat)
    expect(response).to have_http_status(:not_found)
  end
end
