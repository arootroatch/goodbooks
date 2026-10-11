require "rails_helper"

RSpec.describe "Space above tables", js: true do
  let(:gap_script) do
    <<~JS
      [...document.querySelectorAll('main table, main .table-scroll')]
        .filter(el => !el.closest('.card, .table-scroll') || el.matches('.table-scroll'))
        .filter(el => el.previousElementSibling)
        .map(el => el.getBoundingClientRect().top - el.previousElementSibling.getBoundingClientRect().bottom)
    JS
  end

  it "leaves a gap between every table and whatever sits above it" do
    household = create(:household)
    owner = create(:user, :household_owner)
    book = PersonalBookProvisioner.call(household)
    business = BusinessProvisioner.call(build(:business, person: create(:person, household:)), owner:)
    account = create(:account, business: book)
    create(:transaction, account:, category: book.categories.find_by!(name: "Groceries"), amount_cents: -4_200, posted_on: Date.current)
    create(:transaction, account: business.accounts.first, posted_on: Date.current)
    system_sign_in_as owner

    [ business_spending_report_path(book), business_inbox_path(business), business_profit_and_loss_path(business),
      business_clients_path(business) ].each do |path|
      visit path
      gaps = page.evaluate_script(gap_script)
      expect(gaps).not_to be_empty, path
      expect(gaps).to all(be >= 12), "#{path}: #{gaps.inspect}"
    end
  end
end
