require "rails_helper"

RSpec.describe "Goal reports" do
  let!(:book) { create(:business) }
  let!(:checking) { create(:account, business: book, name: "Checking") }

  it "lists a payment goal's linked transactions newest first with a running total" do
    goal = create(:goal, business: book, target: "30,000")
    create(:transaction, account: checking, posted_on: Date.new(2026, 3, 1), payee: "ZELLE TONY", amount_cents: -2_000_00, goal: goal, goal_linked_by: "user")
    create(:transaction, account: checking, posted_on: Date.new(2026, 2, 1), payee: "ZELLE TONY", amount_cents: -1_500_00, goal: goal, goal_linked_by: "user")
    create(:transaction, account: checking, posted_on: Date.new(2026, 4, 1), payee: "ZELLE TONY", amount_cents: -9_00, goal: goal, goal_linked_by: "user", excluded: true)
    sign_in_as user_with_role("viewer", book)
    get business_goal_path(book, goal)
    rows = Nokogiri::HTML(response.body).css(".goal-transactions tbody tr").map { _1.css("td").map { |td| td.text.squish } }
    expect(rows.map(&:first)).to eq([ "2026-03-01", "2026-02-01" ])
    expect(rows.map { _1[4] }).to eq([ "$3,500.00", "$1,500.00" ])
    expect(response.body).to include("$3,500.00 of $30,000.00")
    expect(response.body).not_to include("Unlink")
  end

  it "still lists an archived payment goal's linked transactions" do
    goal = create(:goal, business: book, target: "30,000")
    create(:transaction, account: checking, posted_on: Date.new(2026, 2, 1), payee: "ZELLE TONY", amount_cents: -1_500_00, goal: goal, goal_linked_by: "user")
    create(:transaction, account: checking, posted_on: Date.new(2026, 3, 1), payee: "ZELLE TONY", amount_cents: -2_000_00, goal: goal, goal_linked_by: "user")
    goal.update!(archived_at: Time.current)
    sign_in_as user_with_role("viewer", book)
    get business_goal_path(book, goal)
    expect(response).to have_http_status(:ok)
    rows = Nokogiri::HTML(response.body).css(".goal-transactions tbody tr").map { _1.css("td").map { |td| td.text.squish } }
    expect(rows.map(&:first)).to eq([ "2026-03-01", "2026-02-01" ])
    expect(rows.map { _1[4] }).to eq([ "$3,500.00", "$1,500.00" ])
  end

  it "shows a savings goal's allocation and the account's running balance" do
    savings = create(:account, business: book, kind: "savings", opening_balance: "8,000", opening_balance_on: Date.new(2026, 1, 1))
    nest = create(:goal, :savings, business: book, account: savings, name: "Nest egg", target: "6,000")
    create(:goal, :savings, business: book, account: savings, name: "Truck", target: "10,000")
    create(:transaction, account: savings, posted_on: Date.new(2026, 2, 1), payee: "DEPOSIT", amount_cents: 1_000_00)
    sign_in_as user_with_role("viewer", book)
    get business_goal_path(book, nest)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".goal-allocation").text.squish).to include("Nest egg").and include("Truck").and include("$3,000.00 of $10,000.00")
    expect(page.at_css(".goal-history tbody tr").text.squish).to include("DEPOSIT").and include("$9,000.00")
  end

  it "lets an editor unlink a transaction, which stays unlinked when the goal rematches" do
    goal = create(:goal, business: book)
    txn = create(:transaction, account: checking, payee: "ZELLE TONY", amount_cents: -100_00)
    GoalMatcher.new(book).rematch
    sign_in_as user_with_role("editor", book)
    delete business_goal_link_path(book, goal, txn)
    expect(response).to redirect_to(business_goal_path(book, goal))
    expect(txn.reload.attributes.values_at("goal_id", "goal_linked_by")).to eq([ nil, "user" ])
    goal.update!(match_value: "zelle")
    expect(txn.reload.goal_id).to be_nil
  end

  it "rejects unlinking from viewers and for transactions not on the goal" do
    goal = create(:goal, business: book)
    txn = create(:transaction, account: checking, payee: "ZELLE TONY", amount_cents: -100_00)
    GoalMatcher.new(book).rematch
    sign_in_as user_with_role("viewer", book)
    delete business_goal_link_path(book, goal, txn)
    expect(response).to have_http_status(:forbidden)
    sign_in_as user_with_role("editor", book)
    delete business_goal_link_path(book, goal, create(:transaction, payee: "TONY"))
    expect(response).to have_http_status(:not_found)
    expect(txn.reload.goal).to eq(goal)
  end

  it "404s unlinking through another book's goal and leaves the transaction alone" do
    goal = create(:goal, business: book)
    txn = create(:transaction, account: checking, payee: "ZELLE TONY", amount_cents: -100_00)
    GoalMatcher.new(book).rematch
    sign_in_as user_with_role("editor", book)
    delete business_goal_link_path(book, create(:goal), txn)
    expect(response).to have_http_status(:not_found)
    expect(txn.reload.attributes.values_at("goal_id", "goal_linked_by")).to eq([ goal.id, "matcher" ])
  end
end
