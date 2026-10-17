require "rails_helper"

RSpec.describe "Settings menu", js: true do
  let!(:household) { create(:household) }

  it "collapses by default and remembers when it's opened or closed" do
    system_sign_in_as create(:user, :household_owner)
    visit root_path
    expect(page).to have_no_link("People")

    find("details.nav-section > summary").click
    expect(page).to have_link("People")
    visit root_path
    expect(page).to have_link("People")

    find("details.nav-section > summary").click
    expect(page).to have_no_link("People")
    visit root_path
    expect(page).to have_no_link("People")
  end
end
