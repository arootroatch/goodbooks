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
    expect(page.find(".tithe-summary .tithe-summary-header")).to have_css("h2", text: "Tithe")
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

  it "shows last week's tithe owed, giving, and status in the overview card" do
    last_week_start = Date.current - Date.current.wday - 7
    create(:transaction, account: checking, payee: "TRANSFER FROM PAT", amount_cents: 50_000, posted_on: last_week_start + 2)
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book)
    week = Capybara.string(response.body).find(".tithe-summary .tithe-last-week")
    expect(week).to have_css(".card-title", text: "Last week")
    expect(week).to have_text("#{last_week_start.strftime('%b %-d')} – #{(last_week_start + 6).strftime('%b %-d, %Y')}")
    expect(week.all("dt").map(&:text)).to eq([ "Tithe owed", "Given" ])
    expect(week.all("dd").map(&:text)).to eq([ "$50.00", "$0.00" ])
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
