require "rails_helper"

RSpec.describe "Tithe" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:book) { PersonalBookProvisioner.call(household) }
  let(:checking) { create(:account, business: book) }
  let(:start_on) { Date.current - 14 }

  def seed_week
    create(:transaction, account: checking, payee: "TRANSFER FROM PAT", amount_cents: 150_000, posted_on: start_on)
    create(:transaction, account: checking, payee: "CHECK 1042 GRACE CHURCH", amount_cents: -10_000, posted_on: start_on + 1,
                         category: book.categories.find_by!(name: "Tithe"))
  end

  it "asks the owner for a start date before showing numbers" do
    sign_in_as owner
    get business_tithe_path(book)
    expect(response.body).to include("Track tithe from")
    expect(response.body).not_to include("Behind")
  end

  it "shows the balance, the weekly rows, and a CSV once a start date is set" do
    seed_week
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book)
    expect(response.body).to include("Behind $50.00", "TRANSFER FROM PAT", "CHECK 1042 GRACE CHURCH")
    page = Capybara.string(response.body)
    expect(page.find("header.page-header")).to have_link("Download CSV", href: business_tithe_path(book, format: :csv), class: "button")
    expect(page.find(".tithe-summary .tithe-balance")).to have_css("b.neg", text: "Behind $50.00")
    expect(page.find(".tithe-summary .tithe-balance")).to have_text("Give $50.00 to catch up")
    expect(page.find(".tithe-summary .tithe-balance")).to have_text("This year: owed $150.00 · given $100.00")
    expect(page).to have_css(".tithe-summary + table")
    expect(page.find(".tithe-summary .summary-card-header")).to have_css("h2", text: "Tithe")
    expect(page.find(".tithe-summary")).to have_no_link("Tithe details")
    expect(page).to have_css("td .badge.badge-warn", text: "Partial")
    get business_tithe_path(book, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body.lines.first).to start_with("Week starting,Week ending,Income,Owed")
    expect(response.body.lines.first).to end_with("Balance (positive = behind)\n")
    get root_path
    expect(Capybara.string(response.body).find(".kpi", text: "Tithe")).to have_text("Behind $50.00")
  end

  it "sums up this week's income, tithe owed, and giving in the overview card" do
    seed_week
    create(:transaction, account: checking, payee: "TRANSFER FROM PAT", amount_cents: 50_000, posted_on: Date.current)
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book)
    week = Capybara.string(response.body).find(".tithe-summary .tithe-this-week")
    week_start = Date.current - Date.current.wday
    expect(week).to have_css(".card-title", text: "This week")
    expect(week).to have_text("#{week_start.strftime('%b %-d')} – #{(week_start + 6).strftime('%b %-d, %Y')}")
    expect(week.all("dt").map(&:text)).to eq([ "Income", "Tithe owed", "Given" ])
    expect(week.all("dd").map(&:text)).to eq([ "$500.00", "$50.00", "$0.00" ])
  end

  it "shows last week's income, tithe owed, giving, the balance going into it, and status in the overview card" do
    last_week_start = Date.current - Date.current.wday - 7
    create(:transaction, account: checking, payee: "TRANSFER FROM PAT", amount_cents: 100_000, posted_on: start_on)
    create(:transaction, account: checking, payee: "TRANSFER FROM PAT", amount_cents: 50_000, posted_on: last_week_start + 2)
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book)
    week = Capybara.string(response.body).find(".tithe-summary .tithe-last-week")
    expect(week).to have_css(".card-title", text: "Last week")
    expect(week).to have_text("#{last_week_start.strftime('%b %-d')} – #{(last_week_start + 6).strftime('%b %-d, %Y')}")
    expect(week.all("dt").map(&:text)).to eq([ "Income", "Tithe owed", "Given", "Balance before" ])
    expect(week.all("dd").map(&:text)).to eq([ "$500.00", "$50.00", "$0.00", "Behind $100.00" ])
    expect(week).to have_css(".badge.badge-muted", text: "Open")
  end

  it "leaves last week out when tracking started this week" do
    book.update!(tithe_start_on: Date.current)
    sign_in_as owner
    get business_tithe_path(book)
    expect(Capybara.string(response.body)).to have_no_css(".tithe-last-week")
  end

  it "says when the tithe is caught up" do
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book)
    expect(Capybara.string(response.body).find(".tithe-balance")).to have_text("Even").and have_text("You're caught up.")
  end

  it "saves, rejects, and clears the start date" do
    sign_in_as owner
    patch business_tithe_path(book), params: { business: { tithe_start_on: start_on.iso8601 } }
    expect(response).to redirect_to(business_tithe_path(book))
    expect(book.reload.tithe_start_on).to eq(start_on)

    patch business_tithe_path(book), params: { business: { tithe_start_on: "abc" } }
    expect(flash[:alert]).to eq("Tithe start date is not a valid date.")
    expect(book.reload.tithe_start_on).to eq(start_on)

    patch business_tithe_path(book), params: { business: { tithe_start_on: (Date.current + 1).iso8601 } }
    expect(flash[:alert]).to include("can't be in the future")
    expect(book.reload.tithe_start_on).to eq(start_on)

    patch business_tithe_path(book), params: { business: { tithe_start_on: "" } }
    expect(book.reload.tithe_start_on).to be_nil
  end

  it "rejects a start date before the floor" do
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    patch business_tithe_path(book), params: { business: { tithe_start_on: "0202-01-04" } }
    expect(flash[:alert]).to include("can't be before 2000-01-01")
    expect(book.reload.tithe_start_on).to eq(start_on)
  end

  it "escapes payee text on the tithe page" do
    create(:transaction, account: checking, payee: "<script>alert(1)</script>", amount_cents: 150_000, posted_on: start_on)
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book)
    expect(response.body).to include("&lt;script&gt;")
    expect(response.body).not_to include("<script>alert(1)")
  end

  it "lets editors read but not change the start date" do
    spouse = create(:user)
    create(:person, household: household, user: spouse)
    PersonalBookProvisioner.sync(household)
    sign_in_as spouse
    get business_tithe_path(book)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Track tithe from")
    patch business_tithe_path(book), params: { business: { tithe_start_on: start_on.iso8601 } }
    expect(response).to have_http_status(:forbidden)
  end

  it "lists each week's transactions as rows under the week, with their account" do
    seed_week
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book)
    week = Capybara.string(response.body).find("tbody.tithe-week", text: "TRANSFER FROM PAT")
    expect(week).to have_css("tr.tithe-week-row button[aria-expanded='false']")
    deposit = week.find("tr.tithe-entry[hidden]", text: "TRANSFER FROM PAT", visible: :all)
    expect(deposit).to have_text(checking.name)
    expect(deposit.all("td", visible: :all).map(&:text).values_at(1, 3).map(&:strip)).to eq([ "$1,500.00", "" ])
    check = week.find("tr.tithe-entry", text: "CHECK 1042 GRACE CHURCH", visible: :all)
    expect(check.all("td", visible: :all).map(&:text).values_at(1, 3).map(&:strip)).to eq([ "", "$100.00" ])
    expect(deposit).to have_button("Leave out", visible: :all)
  end

  it "opens the week named in the URL" do
    seed_week
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book, week: Tithe::Ledger.week_start(start_on).iso8601)
    week = Capybara.string(response.body).find("tbody.tithe-week", text: "TRANSFER FROM PAT")
    expect(week).to have_css("tr.tithe-week-row button[aria-expanded='true']")
    expect(week).to have_no_css("tr.tithe-entry[hidden]")
  end

  it "lets the owner choose which accounts' income counts" do
    savings = create(:account, business: book, name: "Savings", kind: "savings")
    create(:transaction, account: savings, payee: "TRANSFER FROM CHECKING", amount_cents: 100_000, posted_on: start_on)
    seed_week
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book)
    expect(Capybara.string(response.body).find("form.tithe-accounts")).to have_checked_field("Savings")
    expect(response.body).to include("Behind $150.00")

    patch business_tithe_accounts_path(book), params: { account_ids: [ checking.id.to_s, create(:account).id.to_s ] }
    expect(response).to redirect_to(business_tithe_path(book))
    expect([ checking.reload.tithable, savings.reload.tithable ]).to eq([ true, false ])
    follow_redirect!
    expect(Capybara.string(response.body).find("form.tithe-accounts")).to have_unchecked_field("Savings")
    expect(response.body).to include("Behind $50.00")
    expect(response.body).not_to include("TRANSFER FROM CHECKING")

    patch business_tithe_accounts_path(book), params: { account_ids: [ "" ] }
    expect(checking.reload.tithable).to be(false)
  end

  it "lets an editor leave a transaction out of the tithe and count it again" do
    seed_week
    book.update!(tithe_start_on: start_on)
    spouse = create(:user)
    create(:person, household: household, user: spouse)
    PersonalBookProvisioner.sync(household)
    sign_in_as spouse
    deposit = checking.transactions.find_by!(payee: "TRANSFER FROM PAT")
    week = Tithe::Ledger.week_start(start_on).iso8601

    post business_transaction_tithe_exclusion_path(book, deposit)
    expect(response).to redirect_to(business_tithe_path(book, week: week, anchor: "week-#{week}"))
    expect(deposit.reload.tithe_excluded).to be(true)
    get business_tithe_path(book)
    expect(response.body).to include("Ahead $100.00")
    row = Capybara.string(response.body).find("tr.tithe-entry", text: "TRANSFER FROM PAT", visible: :all)
    expect(row[:class]).to include("muted")
    expect(row).to have_css(".badge", text: "Left out", visible: :all).and have_button("Count", visible: :all)

    delete business_transaction_tithe_exclusion_path(book, deposit)
    expect(deposit.reload.tithe_excluded).to be(false)
    expect(deposit.excluded).to be(false)
  end

  it "keeps account choices to the owner and exclusions to the personal book" do
    spouse = create(:user)
    create(:person, household: household, user: spouse)
    PersonalBookProvisioner.sync(household)
    book.update!(tithe_start_on: start_on)
    sign_in_as spouse
    get business_tithe_path(book)
    expect(response.body).not_to include("tithe-accounts")
    patch business_tithe_accounts_path(book), params: { account_ids: [ "" ] }
    expect(response).to have_http_status(:forbidden)

    business = create(:business)
    sign_in_as user_with_role("owner", business)
    txn = create(:transaction, account: create(:account, business: business))
    post business_transaction_tithe_exclusion_path(business, txn)
    expect(response).to have_http_status(:not_found)
    patch business_tithe_accounts_path(business), params: { account_ids: [ "" ] }
    expect(response).to have_http_status(:not_found)
  end

  it "is not found for non-members and on business books" do
    business = create(:business)
    accountant = user_with_role("viewer", business)
    sign_in_as accountant
    get business_tithe_path(book)
    expect(response).to have_http_status(:not_found)
    get business_tithe_path(book, format: :csv)
    expect(response).to have_http_status(:not_found)
    sign_in_as user_with_role("owner", business)
    get business_tithe_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
