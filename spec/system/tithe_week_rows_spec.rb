require "rails_helper"

RSpec.describe "Tithe week rows", js: true do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:book) { PersonalBookProvisioner.call(household) }
  let!(:checking) { create(:account, business: book, name: "Joint Checking") }
  let(:start_on) { Date.current - Date.current.wday - 7 }

  it "expands a week into its transactions and leaves one out of the tithe" do
    create(:transaction, account: checking, payee: "PAYROLL", amount_cents: 100_000, posted_on: start_on + 1)
    create(:transaction, account: checking, payee: "TRANSFER FROM SAVINGS", amount_cents: 50_000, posted_on: start_on + 2)
    book.update!(tithe_start_on: start_on)
    system_sign_in_as owner
    visit business_tithe_path(book)
    expect(page).to have_no_text("PAYROLL")

    click_on Capybara.string(page.html).find("#week-#{start_on.iso8601} .tithe-week-toggle").text
    row = find("tr.tithe-entry", text: "TRANSFER FROM SAVINGS")
    expect(row).to have_text("Joint Checking")
    row.click_on "Leave out"

    expect(page).to have_css("tr.tithe-entry .badge", text: "Left out")
    expect(page).to have_text("PAYROLL")
    expect(find("#week-#{start_on.iso8601} tr.tithe-week-row")).to have_text("$1,000.00")
  end
end
