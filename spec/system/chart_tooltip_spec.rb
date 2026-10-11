require "rails_helper"

RSpec.describe "Overview chart tooltip", js: true do
  it "shows the bar's amount as soon as it is hovered" do
    business = create(:business)
    account = create(:account, business:)
    income = create(:category, :income, business:)
    create(:transaction, account:, category: income, posted_on: Date.current.beginning_of_month, amount_cents: 300_000)
    system_sign_in_as user_with_role("viewer", business)
    visit business_path(business)

    find("svg.chart rect.bar-income").hover
    tip = find(".chart-tooltip", wait: 0.2)
    expect(tip).to have_text("#{Date::ABBR_MONTHNAMES[Date.current.month]} income: $3,000.00")
    find("h1").hover
    expect(page).to have_no_css(".chart-tooltip", wait: 0.2)
  end
end
