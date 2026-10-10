require "rails_helper"

RSpec.describe "Businesses" do
  let!(:household) { create(:household) }
  let!(:person) { create(:person, household: household) }
  let(:household_owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, person: person, name: "Pat Consulting"), owner: household_owner) }

  describe "creating" do
    it "lets the household owner create a provisioned business" do
      sign_in_as household_owner
      post businesses_path, params: { business: { name: "Second Gig", person_id: person.id } }
      created = Business.find_by!(name: "Second Gig")
      expect(response).to redirect_to(business_path(created))
      expect(created.accounts.pluck(:name)).to eq([ "Cash" ])
      expect(household_owner.membership_for(created)).to be_owner
    end

    it "re-renders when invalid" do
      sign_in_as household_owner
      post businesses_path, params: { business: { name: "", person_id: person.id } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "forbids everyone else" do
      sign_in_as user_with_role("owner", business)
      get new_business_path
      expect(response).to have_http_status(:forbidden)
      post businesses_path, params: { business: { name: "Nope", person_id: person.id } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "showing" do
    it "shows a business to a viewer" do
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pat Consulting")
    end

    it "is not found for non-members" do
      sign_in_as create(:user)
      get business_path(business)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "editing" do
    it "lets a business owner rename" do
      owner = user_with_role("owner", business)
      sign_in_as owner
      patch business_path(business), params: { business: { name: "Renamed" } }
      expect(business.reload.name).to eq("Renamed")
    end

    it "keeps showing the saved name in the sidebar after a failed rename" do
      sign_in_as user_with_role("owner", business)
      patch business_path(business), params: { business: { name: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      sidebar = Capybara.string(response.body).find("nav.sidebar")
      expect(sidebar).to have_css(".nav-group", text: "Pat Consulting")
      expect(sidebar).to have_css(".switcher summary", text: "Pat Consulting")
    end

    it "forbids editors and viewers" do
      %w[editor viewer].each do |role|
        sign_in_as user_with_role(role, business)
        patch business_path(business), params: { business: { name: "Renamed" } }
        expect(response).to have_http_status(:forbidden)
        delete session_path
      end
    end
  end

  describe "overview" do
    let(:account) { create(:account, business: business, name: "Checking") }
    let(:consulting) { create(:category, :income, business: business, name: "Consulting") }
    let(:travel) { business.categories.find_by!(name: "Travel") }
    let(:page) { Capybara.string(response.body) }

    before { travel_to Time.zone.local(2026, 3, 15, 12) }

    def kpi(label) = page.find(".kpi", text: label)

    it "shows the year's income, expenses, and net profit by default" do
      create(:transaction, account:, category: consulting, posted_on: Date.new(2026, 2, 1), amount_cents: 1_000_000)
      create(:transaction, account:, category: travel, posted_on: Date.new(2026, 2, 5), amount_cents: -250_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(kpi("Income")).to have_text("$10,000.00")
      expect(kpi("Expenses")).to have_text("$2,500.00")
      expect(kpi("Expenses")).to have_text("25% of income")
      expect(kpi("Net profit")).to have_css(".pos", text: "$7,500.00")
    end

    it "omits the net profit footnote when expenses are fully deductible" do
      create(:transaction, account:, category: consulting, posted_on: Date.new(2026, 2, 1), amount_cents: 1_000_000)
      create(:transaction, account:, category: travel, posted_on: Date.new(2026, 2, 5), amount_cents: -250_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(kpi("Net profit (tax basis)")).to have_no_css("em")
    end

    it "explains net profit when deduction limits make it differ from income minus expenses" do
      meals = create(:category, business:, name: "Client meals", deductible_bps: 5_000)
      create(:transaction, account:, category: consulting, posted_on: Date.new(2026, 2, 1), amount_cents: 1_000_000)
      create(:transaction, account:, category: meals, posted_on: Date.new(2026, 2, 5), amount_cents: -200_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(kpi("Expenses")).to have_text("$2,000.00")
      expect(kpi("Net profit (tax basis)")).to have_css(".pos", text: "$9,000.00")
      expect(kpi("Net profit (tax basis)")).to have_css("em", text: "After deduction limits and mileage")
    end

    it "shows negative net profit in red parentheses" do
      create(:transaction, account:, category: travel, posted_on: Date.new(2026, 2, 5), amount_cents: -250_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(kpi("Net profit")).to have_css(".neg", text: "($2,500.00)")
      expect(kpi("Net profit")).to have_no_css(".pos")
      expect(kpi("Expenses")).to have_no_text("of income")
    end

    def period_nav = page.find("nav.segmented[aria-label='Period']")
    def chart = page.find("svg.chart", visible: :all)
    def axis_labels = chart.all("text.chart-axis", visible: :all).map { _1.text(:all) }.grep_v(/\A\$/)

    it "defaults to the current year, charted by month with the month in progress faded" do
      create(:transaction, account:, category: consulting, posted_on: Date.new(2026, 1, 10), amount_cents: 500_000)
      create(:transaction, account:, category: consulting, posted_on: Date.new(2026, 3, 10), amount_cents: 300_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(page.find(".period-step")).to have_text("2026")
      expect(page.find(".period-step")).to have_text("Jan 1 – Dec 31, 2026")
      expect(axis_labels).to eq(Date::ABBR_MONTHNAMES.compact)
      expect(chart["aria-label"]).to eq("Income and expenses by month, 2026")
      expect(chart).to have_css("rect.bar-income", count: 2, visible: :all)
      expect(chart).to have_css("rect.bar-income.faded title", text: "Mar income: $3,000.00", visible: :all)
      expect(period_nav).to have_css('a[aria-current="page"]', count: 1, text: "Year")
    end

    it "charts a month by week and limits the totals to that month" do
      create(:transaction, account:, category: consulting, posted_on: Date.new(2026, 2, 27), amount_cents: 900_000)
      create(:transaction, account:, category: consulting, posted_on: Date.new(2026, 3, 10), amount_cents: 300_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business, period: "month", on: "2026-03-01")
      expect(page.find(".period-step")).to have_text("March 2026")
      expect(kpi("Income")).to have_text("$3,000.00")
      expect(axis_labels).to eq([ "Mar 1", "Mar 2", "Mar 9", "Mar 16", "Mar 23", "Mar 30" ])
      expect(chart["aria-label"]).to eq("Income and expenses by week, March 2026")
      expect(chart).to have_css("rect.bar-income title", text: "Mar 9 income: $3,000.00", visible: :all)
      expect(period_nav).to have_css('a[aria-current="page"]', count: 1, text: "Month")
    end

    it "steps back to an earlier quarter and forward again" do
      create(:transaction, account:, category: consulting, posted_on: Date.new(2025, 11, 3), amount_cents: 100_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business, period: "quarter", on: "2025-10-01")
      step = page.find(".period-step")
      expect(step).to have_text("Q4 2025")
      expect(step).to have_text("Oct 1 – Dec 31, 2025")
      expect(kpi("Income")).to have_text("$1,000.00")
      expect(axis_labels).to eq(%w[Oct Nov Dec])
      expect(chart).to have_no_css("rect.faded", visible: :all)
      expect(step).to have_link("‹", href: business_path(business, period: "quarter", on: "2025-07-01"))
      expect(step).to have_link("›", href: business_path(business, period: "quarter", on: "2026-01-01"))
    end

    it "offers no next step from the period containing today" do
      sign_in_as user_with_role("viewer", business)
      get business_path(business, period: "quarter", on: "2026-02-01")
      expect(page.find(".period-step")).to have_no_link("›")
      expect(page.find(".period-step")).to have_link("‹")
    end

    it "switches kind around today when the period contains it" do
      sign_in_as user_with_role("viewer", business)
      get business_path(business, period: "quarter", on: "2026-01-01")
      expect(period_nav).to have_link("Month", href: business_path(business, period: "month", on: "2026-03-01"))
      expect(period_nav).to have_link("Year", href: business_path(business, period: "year", on: "2026-01-01"))
    end

    it "switches kind around the period's start for a past period" do
      sign_in_as user_with_role("viewer", business)
      get business_path(business, period: "year", on: "2025-01-01")
      expect(period_nav).to have_link("Quarter", href: business_path(business, period: "quarter", on: "2025-01-01"))
    end

    it "falls back to the current year for nonsense params" do
      sign_in_as user_with_role("viewer", business)
      get business_path(business, period: "decade", on: "soon")
      expect(response).to have_http_status(:ok)
      expect(page.find(".period-step")).to have_text("Jan 1 – Dec 31, 2026")
    end

    it "lists the top five expense categories, largest first" do
      %w[A B C D E F].each_with_index do |name, i|
        category = create(:category, business: business, name: "Cat #{name}")
        create(:transaction, account:, category:, posted_on: Date.new(2026, 2, 1), amount_cents: -(i + 1) * 10_000)
      end
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      labels = page.all(".hbar-label").map(&:text)
      expect(labels).to eq([ "Cat F", "Cat E", "Cat D", "Cat C", "Cat B" ])
    end

    it "leaves out expense categories netted negative by refunds" do
      refunds = create(:category, business: business, name: "Refunded Gear")
      create(:transaction, account:, category: refunds, posted_on: Date.new(2026, 2, 1), amount_cents: 5_000)
      create(:transaction, account:, category: travel, posted_on: Date.new(2026, 2, 5), amount_cents: -10_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(page.all(".hbar-label").map(&:text)).to eq([ "Travel" ])
    end

    it "previews the three oldest inbox transactions" do
      [ 1, 2, 3, 4 ].each { |day| create(:transaction, account:, category: nil, payee: "Payee #{day}", posted_on: Date.new(2026, 2, day)) }
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      preview = page.find(".inbox-preview")
      expect(preview).to have_text("4 transactions to categorize")
      expect(preview.all("tbody tr").map { _1.all("td")[1].text }).to eq([ "Payee 1", "Payee 2", "Payee 3" ])
      expect(preview).to have_link("Open inbox →", href: business_inbox_path(business))
    end

    it "renders an empty business with zeros and empty states" do
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(response).to have_http_status(:ok)
      expect(kpi("Income")).to have_text("$0.00")
      expect(page).to have_no_css("svg.chart rect.bar", visible: :all)
      expect(page).to have_text("No expenses")
      expect(page).to have_text("Inbox zero")
    end

    it "keeps the account list and owner-only edit link" do
      account
      sign_in_as user_with_role("owner", business)
      get business_path(business)
      expect(page).to have_text("Checking")
      expect(page).to have_link("Edit business", href: edit_business_path(business))
    end
  end

  describe "dashboard" do
    it "lists only accessible businesses" do
      other = create(:business, name: "Hidden Biz")
      sign_in_as user_with_role("viewer", business)
      get root_path
      expect(response.body).to include("Pat Consulting")
      expect(response.body).not_to include("Hidden Biz")
      expect(other).to be_persisted
    end
  end
end
