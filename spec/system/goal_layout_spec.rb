require "rails_helper"

RSpec.describe "Goal layout", js: true do
  let!(:book) { create(:business) }
  let!(:goal) { create(:goal, business: book, name: "Pay back Uncle Tony", target: "30,000") }

  def rect(selector) = page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().toJSON()")

  before { system_sign_in_as user_with_role("editor", book) }

  it "shows each goal's name beside its bar in the overview widget" do
    visit business_path(book)
    expect(rect(".goal-widget li a")["width"]).to be > 50
  end

  it "makes the header's Edit and Archive buttons the same height" do
    visit business_goal_path(book, goal)
    expect(page).to have_link("Edit")
    expect(rect(".page-actions button")["height"]).to eq(rect(".page-actions a")["height"])
  end

  it "puts Delete goal beside Save goal" do
    visit edit_business_goal_path(book, goal)
    expect(page).to have_button("Delete goal")
    expect(rect("button[form]")["top"]).to eq(rect("input[type=submit][value='Save goal']")["top"])
  end
end
