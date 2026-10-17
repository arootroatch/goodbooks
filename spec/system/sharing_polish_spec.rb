require "rails_helper"

RSpec.describe "Sharing polish" do
  let!(:business) { create(:business, name: "Smith Photography") }
  let!(:owner) { user_with_role("owner", business, household_owner: true, name: "Alex") }
  let!(:accountant) { user_with_role("viewer", business, name: "Avery") }

  it "revokes another session" do
    accountant.sessions.create!(user_agent: "Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0")
    system_sign_in_as accountant
    click_on "Sessions"
    within("tr", text: "Firefox on Linux") { click_on "Revoke" }
    expect(page).to have_content("Session revoked.")
    expect(page).not_to have_content("Firefox on Linux")
  end

  it "removes a user, who then can't sign in, and shows it in the audit log" do
    system_sign_in_as owner
    click_on "Users"
    within("tr", text: "Avery") { click_on "Remove from household" }
    expect(page).to have_content("Avery removed from the household.")
    click_on "Audit log"
    expect(page).to have_content("Removed Avery from the household")
    visit audit_events_path(user_id: owner.id, auditable_type: "Membership")
    expect(page).to have_content("Avery in Smith Photography (viewer)")
    expect(page).to have_content("deleted")
    click_on "Sign out"
    visit new_session_path
    fill_in "email_address", with: accountant.email_address
    fill_in "password", with: AuthHelpers::PASSWORD
    click_on "Sign in"
    expect(page).to have_content("Try another email address or password.")
  end

  it "resolves an error" do
    ErrorEvent.create!(fingerprint: "f", error_class: "RuntimeError", message: "boom", backtrace: "app/x.rb:1",
                       first_seen_at: 1.hour.ago, last_seen_at: 1.hour.ago)
    system_sign_in_as owner
    click_on "Errors"
    click_on "Resolve"
    expect(page).to have_content("Error resolved.")
    expect(page).to have_content("No open errors.")
  end
end
