require "rails_helper"

RSpec.describe "Reordering rules", js: true do
  let!(:business) { create(:business) }
  let!(:category) { create(:category, business: business, name: "Software") }
  let!(:first_rule) { create(:rule, business: business, value: "alpha", category: category) }
  let!(:second_rule) { create(:rule, business: business, value: "bravo", category: category) }

  it "saves the new order after dragging a rule to the top" do
    system_sign_in_as user_with_role("editor", business)
    visit business_rules_path(business)
    handle = find("#rule_#{second_rule.id} .drag-handle").native
    target = find("#rule_#{first_rule.id}").native
    page.driver.browser.action.click_and_hold(handle).move_to(target, 0, -5).pause(duration: 0.2).move_to(target, 0, -10).release.perform
    expect(page).to have_css("tbody[data-sortable-state='saved']")
    expect(page).to have_css("tbody tr:first-child#rule_#{second_rule.id}")
    expect(business.rules.ordered.to_a).to eq([second_rule, first_rule])
  end

  it "shows no drag handles to viewers" do
    system_sign_in_as user_with_role("viewer", business)
    visit business_rules_path(business)
    expect(page).to have_content("alpha")
    expect(page).to have_no_css(".drag-handle")
  end
end
