require "rails_helper"

RSpec.describe "Sidebar on a short window", js: true do
  it "scrolls instead of collapsing the section headings" do
    business = create(:business)
    system_sign_in_as user_with_role("owner", business)
    page.driver.browser.manage.window.resize_to(1280, 500)
    visit business_path(business)

    heights = page.evaluate_script("[...document.querySelectorAll('.sidebar .nav-group')].map(el => el.getBoundingClientRect().height)")
    expect(heights).to all(be > 10)
    expect(page.evaluate_script("document.querySelector('.sidebar').scrollHeight > document.querySelector('.sidebar').clientHeight")).to be(true)
  end
end
