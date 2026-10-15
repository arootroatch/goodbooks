require "rails_helper"

RSpec.describe "Goals" do
  let!(:book) { create(:business) }
  let!(:checking) { create(:account, business: book, name: "Checking") }

  it "backfills a payment goal, shows it on the overview, and keeps an unlink" do
    create(:transaction, account: checking, posted_on: Date.new(2026, 2, 1), payee: "ZELLE TONY RUSSO", amount_cents: -1_500_00)
    create(:transaction, account: checking, posted_on: Date.new(2026, 3, 1), payee: "ZELLE TONY RUSSO", amount_cents: -2_000_00)
    system_sign_in_as user_with_role("editor", book)
    visit business_goals_path(book)
    click_on "New goal"
    fill_in "Name", with: "Pay back Uncle Tony"
    fill_in "Target", with: "30,000"
    fill_in "goal[match_value]", with: "tony"
    click_on "Save goal"
    expect(page).to have_content("Goal saved. 2 existing transactions linked.")

    visit business_path(book)
    within(".goal-widget") do
      expect(page).to have_content("$3,500.00 of $30,000.00")
      click_on "Pay back Uncle Tony"
    end
    within(".goal-transactions tbody tr:last-child") { click_on "Unlink" } # rack_test: no JS, so no confirm dialog
    expect(page).to have_content("Transaction unlinked.")
    expect(page).to have_content("$2,000.00 of $30,000.00")

    click_on "Edit"
    fill_in "goal[match_value]", with: "zelle"
    click_on "Save goal"
    # The hand-unlinked $1,500 row stays out; the $2,000 matcher row is cleared and relinked by the new matcher.
    expect(page).to have_content("Goal saved. 1 existing transaction linked.")
    expect(page).to have_content("$2,000.00 of $30,000.00")
  end

  it "waterfalls two savings goals and flips the allocation on reorder", js: true do
    savings = create(:account, business: book, name: "Savings", kind: "savings", opening_balance: "8,000", opening_balance_on: Date.new(2026, 1, 1))
    nest = create(:goal, :savings, business: book, account: savings, name: "Nest egg", target: "6,000")
    truck = create(:goal, :savings, business: book, account: savings, name: "Truck", target: "10,000")
    system_sign_in_as user_with_role("editor", book)
    visit business_path(book)
    within(".goal-widget") do
      expect(page).to have_content("$6,000.00 of $6,000.00").and have_content("Met").and have_content("$2,000.00 of $10,000.00")
    end

    visit business_goals_path(book)
    handle = find("#goal_#{truck.id} .drag-handle").native
    target = find("#goal_#{nest.id}").native
    page.driver.browser.action.click_and_hold(handle).move_to(target, 0, -5).pause(duration: 0.2).move_to(target, 0, -10).release.perform
    expect(page).to have_css("tbody[data-sortable-state='saved']")
    visit business_path(book)
    within(".goal-widget") { expect(page).to have_content("$8,000.00 of $10,000.00").and have_content("$0.00 of $6,000.00") }
  end
end
