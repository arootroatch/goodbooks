require "rails_helper"

RSpec.describe "Goals" do
  let!(:book) { create(:business) }
  let!(:savings) { create(:account, business: book, name: "Savings", kind: "savings", opening_balance: "8,000", opening_balance_on: Date.new(2026, 1, 1)) }
  let(:payment_params) { { name: "Pay back Uncle Tony", kind: "payments", target: "30,000", target_date: "",
                           match_field: "payee", match_operator: "contains", match_value: "tony", match_amount_min: "", match_amount_max: "" } }

  it "lets an editor create a payment goal and reports how many transactions it linked" do
    create(:transaction, account: savings, payee: "ZELLE TONY", amount_cents: -1_500_00)
    sign_in_as user_with_role("editor", book)
    post business_goals_path(book), params: { goal: payment_params }
    expect(response).to redirect_to(business_goals_path(book))
    expect(flash[:notice]).to eq("Goal saved. 1 existing transaction linked.")
    expect(book.goals.sole).to have_attributes(name: "Pay back Uncle Tony", target_cents: 30_000_00, kind: "payments")
  end

  it "creates a savings goal on an account in the book" do
    sign_in_as user_with_role("editor", book)
    post business_goals_path(book), params: { goal: { name: "Nest egg", kind: "savings", target: "6,000", account_id: savings.id } }
    expect(book.goals.sole).to have_attributes(account: savings, kind: "savings")
    expect(flash[:notice]).to eq("Goal saved.")
  end

  it "re-renders with errors for another book's account or a credit account" do
    sign_in_as user_with_role("editor", book)
    post business_goals_path(book), params: { goal: { name: "x", kind: "savings", target: "1", account_id: create(:account).id } }
    expect(response).to have_http_status(:unprocessable_content)
    post business_goals_path(book), params: { goal: { name: "x", kind: "savings", target: "1",
                                                      account_id: create(:account, business: book, kind: "credit").id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Goal.count).to eq(0)
  end

  it "ignores a kind change on update" do
    goal = create(:goal, business: book)
    sign_in_as user_with_role("editor", book)
    patch business_goal_path(book, goal), params: { goal: payment_params.merge(kind: "savings", name: "Tony") }
    expect(goal.reload).to have_attributes(kind: "payments", name: "Tony")
  end

  it "lists active goals with progress, and archived goals under Completed" do
    create(:goal, :savings, business: book, account: savings, name: "Nest egg", target: "6,000")
    create(:goal, business: book, name: "Old loan", archived_at: Time.current)
    sign_in_as user_with_role("viewer", book)
    get business_goals_path(book)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".goal-list").text).to include("Nest egg").and include("$6,000.00 of $6,000.00").and include("Met")
    expect(page.at_css(".goal-completed").text).to include("Old loan")
    expect(page.css(".drag-handle")).to be_empty
    expect(response.body).not_to include("New goal")
  end

  it "reorders, archives, unarchives and deletes" do
    a = create(:goal, business: book)
    b = create(:goal, business: book)
    sign_in_as user_with_role("editor", book)
    patch move_business_goal_path(book, b), params: { position: 1 }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(book.goals.ordered).to eq([ b, a ])
    patch archive_business_goal_path(book, a)
    expect(a.reload).to be_archived
    patch unarchive_business_goal_path(book, a)
    expect(a.reload).not_to be_archived
    delete business_goal_path(book, a)
    expect(response).to redirect_to(business_goals_path(book))
    expect(Goal.exists?(a.id)).to be(false)
  end

  it "forbids viewers from writing and hides other books' goals" do
    goal = create(:goal, business: book)
    sign_in_as user_with_role("viewer", book)
    post business_goals_path(book), params: { goal: payment_params }
    expect(response).to have_http_status(:forbidden)
    patch move_business_goal_path(book, goal), params: { position: 1 }, as: :json
    expect(response).to have_http_status(:forbidden)
    patch archive_business_goal_path(book, goal)
    expect(response).to have_http_status(:forbidden)
    patch unarchive_business_goal_path(book, goal)
    expect(response).to have_http_status(:forbidden)
    delete business_goal_path(book, goal)
    expect(response).to have_http_status(:forbidden)

    other = create(:goal)
    sign_in_as user_with_role("editor", book)
    patch business_goal_path(book, other), params: { goal: { name: "x" } }
    expect(response).to have_http_status(:not_found)
    get business_goals_path(other.business)
    expect(response).to have_http_status(:not_found)
  end

  it "shows Goals in the book's sidebar" do
    sign_in_as user_with_role("viewer", book)
    get business_path(book)
    expect(response.body).to include(%(href="#{business_goals_path(book)}"))
  end

  it "creates a hand-only payment goal from exactly what the form posts" do
    sign_in_as user_with_role("editor", book)
    post business_goals_path(book), params: { goal: payment_params.merge(match_value: "") }
    expect(response).to redirect_to(business_goals_path(book))
    goal = book.goals.sole
    expect(goal.matcher?).to be(false)
    expect(goal).to have_attributes(match_field: nil, match_operator: nil, match_amount_min_cents: nil, match_amount_max_cents: nil)
  end

  it "turns a matcher goal hand-only when its text is blanked, clearing its matcher links" do
    txn = create(:transaction, account: savings, payee: "ZELLE TONY", amount_cents: -1_500_00)
    goal = create(:goal, business: book, match_field: "payee", match_operator: "contains", match_value: "tony")
    expect(txn.reload.goal).to eq(goal)
    sign_in_as user_with_role("editor", book)
    patch business_goal_path(book, goal), params: { goal: payment_params.merge(match_value: "") }
    expect(goal.reload.matcher?).to be(false)
    expect(txn.reload.goal).to be_nil
  end

  it "reorders active goals by their position among active rows, skipping archived ones" do
    a = create(:goal, business: book)
    create(:goal, business: book, archived_at: Time.current)
    c = create(:goal, business: book)
    sign_in_as user_with_role("editor", book)
    patch move_business_goal_path(book, a), params: { position: 2 }, as: :json
    expect(book.goals.active.ordered).to eq([ c, a ])
  end

  it "links an archived goal's report from Completed, without a progress bar for savings" do
    goal = create(:goal, :savings, business: book, account: savings, name: "Old fund", target: "6,000", archived_at: Time.current)
    sign_in_as user_with_role("viewer", book)
    get business_goals_path(book)
    expect(Nokogiri::HTML(response.body).at_css(".goal-completed a[href='#{business_goal_path(book, goal)}']")).to be_present
    get business_goal_path(book, goal)
    page = Nokogiri::HTML(response.body)
    expect(page.css(".goal-track")).to be_empty
    expect(response.body).to include("Archived").and include("$6,000.00")
    expect(page.css(".goal-allocation")).to be_empty
  end

  it "renames a savings goal whose account was archived later" do
    goal = create(:goal, :savings, business: book, account: savings, target: "6,000")
    savings.update!(archived_at: Time.current)
    sign_in_as user_with_role("editor", book)
    get edit_business_goal_path(book, goal)
    expect(Nokogiri::HTML(response.body).css("select#goal_account_id option").map { _1["value"] }).to include(savings.id.to_s)
    patch business_goal_path(book, goal), params: { goal: { name: "Renamed", account_id: savings.id } }
    expect(response).to redirect_to(business_goals_path(book))
    expect(goal.reload.name).to eq("Renamed")
  end
end
