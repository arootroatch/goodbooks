require "rails_helper"

RSpec.describe "Sales tax on the dashboard" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let(:account) { create(:account, business: business) }

  it "shows the next due date and owed balance, and warns about overdue periods" do
    travel_to Date.new(2026, 5, 1) do
      create(:sales_tax_profile, business: business)
      sales = create(:category, :income, business: business, name: "Sales")
      create(:transaction, account: account, category: sales, amount_cents: 10_925, sales_tax_cents: 925, posted_on: Date.new(2026, 2, 3))
      sign_in_as user_with_role("viewer", business)
      get root_path
      expect(response.body).to include("next due Jul 20", "owed $9.25")
      expect(response.body).to include("Sales tax for Pat Consulting", "Q1 2026", "isn't filed")
      get business_path(business)
      expect(response.body).to include("next due Jul 20", "isn't filed")
    end
  end

  it "shows nothing for businesses without sales tax" do
    sign_in_as user_with_role("owner", business)
    get root_path
    expect(response.body).not_to include("next due")
  end
end
