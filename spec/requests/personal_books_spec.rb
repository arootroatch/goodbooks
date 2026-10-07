require "rails_helper"

RSpec.describe "Personal book" do
  let!(:household) { create(:household) }

  it "lets the household owner set it up from the dashboard" do
    owner = create(:user, :household_owner)
    sign_in_as owner
    get root_path
    expect(response.body).to include("Set up personal book")
    post personal_book_path
    book = Business.personal.sole
    expect(response).to redirect_to(business_path(book))
    get root_path
    expect(response.body).to include(%(href="#{business_path(book)}"))
    expect(response.body).not_to include("Set up personal book")
  end

  it "is not found for anyone else" do
    business = create(:business)
    sign_in_as user_with_role("owner", business)
    post personal_book_path
    expect(response).to have_http_status(:not_found)
    expect(Business.personal).to be_empty
  end
end
