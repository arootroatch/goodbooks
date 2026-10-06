require "rails_helper"

RSpec.describe "Receivables summary" do
  let!(:business) { create(:business, name: "Pat Consulting") }

  it "shows outstanding and overdue on the dashboard and the business page" do
    create(:invoice, business: business, amount_cents: 120_000, due_date: Date.current - 3)
    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(response.body).to include("Outstanding $1,200.00", "Overdue $1,200.00")
    get business_path(business)
    expect(response.body).to include("Outstanding $1,200.00")
  end

  it "shows nothing when nothing is owed" do
    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(response.body).not_to include("Outstanding")
  end
end
