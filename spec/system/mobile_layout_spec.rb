require "rails_helper"

RSpec.describe "Phone-width layout", js: true do
  let!(:book) { create(:business) }
  let(:account) { create(:account, business: book, name: "Business Checking") }

  before do
    create(:transaction, account: account, payee: "TRANSFER FROM SOUND ROOTS PRODUCTIONS", amount_cents: 245_000, posted_on: Date.current)
    system_sign_in_as user_with_role("editor", book)
    # resize_to stops at Chrome's 500px minimum window width; emulation reaches a real phone width.
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: true)
  end

  after { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  def overflow = page.evaluate_script(<<~JS)
    (() => {
      const main = document.querySelector('.app-main');
      return { page: document.documentElement.scrollWidth - document.documentElement.clientWidth,
               main: main.scrollWidth - main.clientWidth };
    })()
  JS

  it "stacks a wide table into labelled cards instead of scrolling sideways" do
    visit business_transactions_path(book)
    row = find("tbody tr", text: "TRANSFER FROM SOUND ROOTS")

    expect(overflow).to eq("page" => 0, "main" => 0)
    expect(row.find("td", text: "Business Checking")["data-label"]).to eq("Account")
    expect(row.evaluate_script("getComputedStyle(this).display")).to eq("block")
    expect(page).to have_no_css("thead", visible: :visible)
  end

  it "keeps a narrow statement table as a table" do
    visit business_profit_and_loss_path(book)
    expect(overflow).to eq("page" => 0, "main" => 0)
    expect(find("tbody tr", match: :first).evaluate_script("getComputedStyle(this).display")).to eq("table-row")
  end

  it "uses 16px form fields so iOS does not zoom in on focus" do
    visit business_transactions_path(book)
    expect(find("input[name=q]").evaluate_script("getComputedStyle(this).fontSize")).to eq("16px")
  end

  it "starts a short page right under the top bar" do
    visit business_rules_path(book)
    expect(find("h1").evaluate_script("this.getBoundingClientRect().top")).to be < 80
  end

  it "fits the goal form's sentence-style fields" do
    visit new_business_goal_path(book)
    expect(page).to have_field("goal[match_value]")
    expect(overflow).to eq("page" => 0, "main" => 0)
  end

  it "fits the dashboard goal widget" do
    create(:goal, business: book, name: "Pay back Uncle Tony", target: "30,000")
    visit business_path(book)
    expect(page).to have_css(".goal-widget li")
    expect(overflow).to eq("page" => 0, "main" => 0)
  end
end
