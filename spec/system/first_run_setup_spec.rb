require "rails_helper"

RSpec.describe "First-run setup", js: true do
  it "creates the household, enrolls two-factor, and shows the recovery codes" do
    visit root_path
    fill_in "Household name", with: "Test Household"
    fill_in "Your name", with: "Pat Tester"
    fill_in "Email address", with: "pat@example.com"
    fill_in "Password", with: "correct horse battery", match: :prefer_exact
    fill_in "Password confirmation", with: "correct horse battery"
    click_button "Create household"

    expect(page).to have_text("Set up two-factor authentication")
    fill_in "Code", with: User.find_by!(email_address: "pat@example.com").totp.now
    click_button "Verify"

    expect(page).to have_css("h1", text: "Save your recovery codes")
    expect(page).to have_css(".recovery-code", count: User::TwoFactor::RECOVERY_CODE_COUNT)
    click_link "Continue"
    expect(page).to have_css("h1", text: "Household")
  end
end
