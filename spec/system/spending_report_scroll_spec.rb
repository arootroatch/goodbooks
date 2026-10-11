require "rails_helper"

RSpec.describe "Spending report on a narrow window", js: true do
  it "scrolls the month columns inside the table with Category and Total frozen" do
    household = create(:household)
    owner = create(:user, :household_owner)
    book = PersonalBookProvisioner.call(household)
    create(:transaction, account: create(:account, business: book), category: book.categories.find_by!(name: "Groceries"),
                         amount_cents: -4_200, posted_on: Date.current)
    system_sign_in_as owner
    page.driver.browser.manage.window.resize_to(1000, 800)
    visit business_spending_report_path(book, from: Date.current.prev_year.beginning_of_year, to: Date.current)

    script = <<~JS
      (() => {
        const main = document.querySelector('.app-main');
        const scroller = document.querySelector('.table-scroll');
        scroller.scrollLeft = 300;
        const box = scroller.getBoundingClientRect();
        const row = [...scroller.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('Groceries'));
        return {
          mainOverflows: main.scrollWidth > main.clientWidth,
          scrolled: scroller.scrollLeft,
          firstLeft: row.firstElementChild.getBoundingClientRect().left - box.left,
          lastRight: box.right - row.lastElementChild.getBoundingClientRect().right
        };
      })()
    JS
    result = page.evaluate_script(script)
    expect(result["mainOverflows"]).to be(false)
    expect(result["scrolled"]).to eq(300)
    expect(result["firstLeft"]).to be_within(2).of(0)
    expect(result["lastRight"]).to be_within(2).of(0)
  end
end
