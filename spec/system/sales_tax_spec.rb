require "rails_helper"

RSpec.describe "Sales tax" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, household: household, name: "Pat Consulting"), owner: owner) }

  it "records a Stripe payout's fee and tax, remits, files, and shows the period paid" do
    travel_to Date.new(2026, 4, 6) do
      system_sign_in_as owner
      visit business_sales_tax_profile_path(business)
      select "Quarterly", from: "Filing frequency"
      fill_in "Default rate (%)", with: "9.25"
      fill_in "Collecting since", with: "2026-01-01"
      click_on "Save"
      expect(page).to have_content("Sales tax settings saved.")

      visit new_business_transaction_path(business)
      fill_in "Date", with: "2026-03-13"
      fill_in "Payee", with: "STRIPE PAYOUT"
      fill_in "Amount", with: "970.70"
      choose "Money in"
      select "Sales", from: "Category"
      fill_in "Processor fee", with: "29.30"
      click_on "Tax-inclusive at default rate (9.25%)"
      expect(page).to have_content("Sales tax set to $84.67 (tax-inclusive at 9.25%).")

      visit new_business_transaction_path(business)
      fill_in "Date", with: "2026-04-06"
      fill_in "Payee", with: "TN DEPT OF REVENUE"
      fill_in "Amount", with: "84.67"
      choose "Money out"
      select "Sales tax remittance", from: "Category"
      click_on "Create Transaction"

      visit business_sales_tax_period_path(business, "2026-01-01")
      expect(page).to have_content("Tax collected $84.67")
      expect(page).to have_content("Remitted $84.67")
      fill_in "Confirmation number", with: "TN123"
      click_on "Mark filed"
      expect(page).to have_content("Period marked filed.")
      expect(page).to have_content("Paid")
    end
  end
end
