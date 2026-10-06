require "rails_helper"

RSpec.describe "Categories" do
  let!(:business) { create(:business) }
  let!(:category) { create(:category, business: business, name: "Office expense") }

  it "lists categories for viewers" do
    sign_in_as user_with_role("viewer", business)
    get business_categories_path(business)
    expect(response.body).to include("Office expense")
  end

  it "lets editors create with a deductible percent" do
    sign_in_as user_with_role("editor", business)
    post business_categories_path(business),
      params: { category: { name: "Client meals", kind: "expense", schedule_c_line: "24b", deductible_percent: "50" } }
    expect(response).to redirect_to(business_categories_path(business))
    expect(business.categories.find_by!(name: "Client meals").deductible_bps).to eq(5000)
  end

  it "re-renders on a line that doesn't match the kind" do
    sign_in_as user_with_role("editor", business)
    post business_categories_path(business), params: { category: { name: "Bad", kind: "income", schedule_c_line: "18", deductible_percent: "100" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "lets editors archive" do
    sign_in_as user_with_role("editor", business)
    patch business_category_path(business, category), params: { category: { archived: "1" } }
    expect(category.reload).to be_archived
  end

  it "forbids viewers from writing" do
    sign_in_as user_with_role("viewer", business)
    post business_categories_path(business), params: { category: { name: "X", kind: "expense", schedule_c_line: "18" } }
    expect(response).to have_http_status(:forbidden)
    patch business_category_path(business, category), params: { category: { name: "Y" } }
    expect(response).to have_http_status(:forbidden)
  end

  it "is not found for non-members" do
    sign_in_as create(:user)
    get business_categories_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
