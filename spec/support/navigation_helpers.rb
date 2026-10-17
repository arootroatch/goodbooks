module SystemNavigationHelpers
  # The sidebar's Settings section starts collapsed away from its own pages.
  def open_settings_menu
    return if page.has_css?("details.nav-section[open]", wait: 0)

    find("details.nav-section > summary").click
    expect(page).to have_css("details.nav-section[open]")
  end
end

RSpec.configure do |config|
  config.include SystemNavigationHelpers, type: :system
end
