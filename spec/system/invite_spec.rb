require "rails_helper"

RSpec.describe "Inviting the accountant" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:owner) { user_with_role("owner", business) }

  it "creates a link that a new user can join with" do
    system_sign_in_as owner
    visit new_invite_path
    fill_in "Email (optional)", with: "acct@example.com"
    select "Viewer", from: "Pat Consulting"
    click_on "Create invite"
    join_url = find("#join-url").text
    click_on "Sign out"

    uri = URI(join_url)
    visit "#{uri.path}?#{uri.query}"
    fill_in "Name", with: "Avery Accountant"
    fill_in "Password", with: AuthHelpers::PASSWORD
    fill_in "Password confirmation", with: AuthHelpers::PASSWORD
    click_on "Join"
    expect(page).to have_content("Set up two-factor authentication")
  end
end
