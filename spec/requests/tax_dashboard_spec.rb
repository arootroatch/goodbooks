require "rails_helper"

RSpec.describe "Estimated tax on the dashboard" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }
  let!(:owner) { create(:user, :household_owner).tap { create(:membership, user: _1, business:, role: "owner") } }

  around { |example| travel_to(Date.new(2026, 5, 1)) { example.run } }

  it "shows the next installment with the IRS link and a link to the taxes page" do
    create(:tax_parameters, :federal_2026)
    sign_in_as owner
    get root_path
    card = Nokogiri::HTML(response.body).at_css(".tax-due")
    expect(card.at_css("h2").text).to include("Next estimated tax")
    expect(card.text).to include("Pay at least").and include("Jun 15, 2026")
    expect(card.at_css("a[target='_blank']")["href"]).to eq(Household::DEFAULT_IRS_PAYMENT_URL)
    expect(card.at_css("a[href='#{tax_year_path(2026)}']")).to be_present
  end

  it "is hidden when the year's federal figures are incomplete" do
    create(:tax_parameters)
    sign_in_as owner
    get root_path
    expect(response.body).not_to include("tax-due")
  end

  it "is hidden from a user without household access" do
    create(:tax_parameters, :federal_2026)
    other = create(:business, household:)
    sign_in_as user_with_role("owner", other)
    get root_path
    expect(response.body).not_to include("tax-due")
  end
end
