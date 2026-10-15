require "rails_helper"

RSpec.describe "Goal widgets" do
  let!(:household) { create(:household) }

  it "shows the book's active goals on its overview, linking to each report" do
    book = create(:business)
    goal = create(:goal, business: book, name: "Pay back Uncle Tony", target: "30,000")
    sign_in_as user_with_role("viewer", book)
    get business_path(book)
    widget = Nokogiri::HTML(response.body).at_css(".goal-widget")
    expect(widget.text).to include("Pay back Uncle Tony").and include("$0.00 of $30,000.00")
    expect(widget.at_css("a[href='#{business_goal_path(book, goal)}']")).to be_present
  end

  it "hides the widget when the book has no active goals" do
    book = create(:business)
    create(:goal, business: book, archived_at: Time.current)
    sign_in_as user_with_role("viewer", book)
    get business_path(book)
    expect(response.body).not_to include("goal-widget")
  end

  it "shows personal goals in the dashboard's Personal section, and not business goals" do
    owner = create(:user, :household_owner)
    studio = BusinessProvisioner.call(build(:business, person: create(:person, household:), name: "Studio"), owner:)
    personal = PersonalBookProvisioner.call(household)
    create(:goal, business: personal, name: "Truck fund", match_field: nil, match_operator: nil, match_value: nil)
    create(:goal, business: studio, name: "Business loan")
    sign_in_as owner
    get root_path
    widget = Nokogiri::HTML(response.body).at_css(".personal-summary .goal-widget")
    expect(widget.text).to include("Truck fund")
    expect(response.body).not_to include("Business loan")
  end
end
