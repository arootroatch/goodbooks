require "rails_helper"

RSpec.describe "Transaction filters", js: true do
  let!(:business) { create(:business) }
  let(:account) { create(:account, business:) }
  let(:fuel) { create(:category, business:, name: "Fuel") }
  let(:meals) { create(:category, business:, name: "Meals") }

  before do
    create(:transaction, account:, category: fuel, payee: "Shell Station")
    create(:transaction, account:, category: meals, payee: "Corner Cafe")
    system_sign_in_as user_with_role("viewer", business)
    visit business_transactions_path(business)
  end

  it "has no filter button" do
    expect(page).to have_no_button("Filter")
  end

  it "filters as soon as a select changes and keeps the url in sync" do
    select "Fuel", from: "category_id"

    expect(page).to have_no_text("Corner Cafe")
    expect(page).to have_text("Shell Station")
    expect(page).to have_current_path(/category_id=#{fuel.id}/)
  end

  it "filters while typing a search without losing focus" do
    fill_in "q", with: "cafe"

    expect(page).to have_no_text("Shell Station")
    expect(page).to have_text("Corner Cafe")
    expect(page.evaluate_script("document.activeElement.name")).to eq("q")
  end
end
