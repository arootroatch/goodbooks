require "rails_helper"

RSpec.describe "Recording an estimated payment" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, household:, name: "Pat Consulting"), owner:) }
  let!(:personal) { PersonalBookProvisioner.call(household) }

  it "picks the IRS debit and sees the amount due drop" do
    travel_to Date.new(2026, 5, 1) do
      create(:tax_parameters, :federal_2026)
      income = business.categories.find_by!(schedule_c_line: "1")
      create(:transaction, account: business.accounts.first, category: income, posted_on: Date.new(2026, 2, 1), amount_cents: 2_500_000)
      create(:transaction, account: create(:account, business: personal, name: "Joint Checking"), payee: "IRS USATAXPYMT",
                           posted_on: Date.new(2026, 4, 14), amount_cents: -100_000)

      system_sign_in_as owner
      visit tax_year_path(2026)
      before = find(".tax-due strong", match: :first).text
      click_on "Record a payment"
      fill_in "Payee contains", with: "IRS"
      click_on "Search"
      click_on "Use this"
      expect(page).to have_content("Payment recorded.")
      expect(page).to have_content("IRS USATAXPYMT · Joint Checking")
      expect(find(".tax-due strong", match: :first).text).not_to eq(before)
    end
  end
end
