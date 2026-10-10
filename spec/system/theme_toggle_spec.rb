require "rails_helper"

RSpec.describe "Theme toggle", js: true do
  let!(:business) { create(:business) }

  it "switches theme without reloading and remembers it" do
    system_sign_in_as user_with_role("viewer", business)
    page.execute_script("window.__noReload = true")

    within(".theme-toggle") { click_button "Dark" }

    expect(page).to have_css("html[data-theme='dark']")
    expect(page.evaluate_script("window.__noReload")).to be(true)
    expect(page).to have_css(".theme-toggle button[aria-pressed='true']", text: "Dark")

    visit root_path
    expect(page).to have_css("html[data-theme='dark']")

    within(".theme-toggle") { click_button "System" }
    expect(page).to have_no_css("html[data-theme]")
  end
end
