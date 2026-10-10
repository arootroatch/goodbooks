require "rails_helper"

RSpec.describe "Sidebar drawer", js: true do
  let!(:business) { create(:business) }

  after { page.current_window.resize_to(1400, 900) }

  it "hides the sidebar behind a menu button on narrow screens" do
    system_sign_in_as user_with_role("viewer", business)
    page.current_window.resize_to(600, 900)
    visit root_path

    expect(page).to have_no_css("nav.sidebar", visible: :visible)
    click_button "Menu"
    expect(page).to have_css("nav.sidebar", visible: :visible)
    expect(page).to have_button("Menu", exact: true) { _1["aria-expanded"] == "true" }
    click_button "Menu"
    expect(page).to have_no_css("nav.sidebar", visible: :visible)
  end
end
