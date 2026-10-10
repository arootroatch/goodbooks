require "rails_helper"

RSpec.describe "Invoice reports" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:other_business) { create(:business, name: "Jordan Design Studio") }
  let!(:overdue) { create(:invoice, business: business, number: "INV-OLD", due_date: Date.current - 45, issue_date: Date.current - 75) }
  let!(:theirs) { create(:invoice, business: other_business, number: "JDS-1", due_date: Date.current + 10, issue_date: Date.current) }

  def household_user
    create(:user).tap do |user|
      [ business, other_business ].each { create(:membership, user: user, business: _1, role: "viewer") }
    end
  end

  it "shows the business aging report and its CSV to viewers" do
    sign_in_as user_with_role("viewer", business)
    get business_invoice_aging_path(business)
    expect(response.body).to include("31–60 days", "INV-OLD")
    expect(response.body).not_to include("JDS-1")
    get business_invoice_aging_path(business, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("INV-OLD")
  end

  it "shows the Business column only in the household aging report" do
    sign_in_as household_user
    get business_invoice_aging_path(business)
    expect(response.body).not_to include("<th>Business</th>")
    get household_invoice_aging_path
    expect(response.body).to include("<th>Business</th>")
  end

  it "links to household aging from the household nav" do
    sign_in_as household_user
    get household_profit_and_loss_path
    expect(response.body).to include(%(href="#{household_invoice_aging_path}"))
  end

  it "exports the filtered invoice list as CSV" do
    sign_in_as user_with_role("viewer", business)
    get business_invoices_path(business, format: :csv, status: "overdue")
    expect(response.media_type).to eq("text/csv")
    expect(CSV.parse(response.body).map(&:first)).to eq([ "Number", "INV-OLD" ])
  end

  it "shows household invoices and aging across businesses" do
    sign_in_as household_user
    get household_invoices_path
    expect(response.body).to include("INV-OLD", "JDS-1", "Jordan Design Studio")
    get household_invoice_aging_path
    expect(response.body).to include("INV-OLD", "JDS-1")
    get household_invoices_path(format: :csv)
    expect(response.body).to include("JDS-1")
  end

  it "404s household screens for users missing a business" do
    sign_in_as user_with_role("owner", business)
    get household_invoices_path
    expect(response).to have_http_status(:not_found)
    get household_invoice_aging_path
    expect(response).to have_http_status(:not_found)
  end

  it "404s the business aging report for non-members" do
    sign_in_as create(:user)
    get business_invoice_aging_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
