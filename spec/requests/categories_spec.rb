require "rails_helper"

RSpec.describe "Categories" do
  it "refuses to change kind while deposits are linked to invoices" do
    payment = create(:invoice_payment)
    linked = payment.deposit.category
    sign_in_as user_with_role("owner", linked.business)
    patch business_category_path(linked.business, linked), params: { category: { kind: "expense", schedule_c_line: "18" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(linked.reload).to be_income
  end

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

  it "shows new form for editors" do
    sign_in_as user_with_role("editor", business)
    get new_business_category_path(business)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("New category")
  end

  it "shows edit form for editors with archived checkbox" do
    sign_in_as user_with_role("editor", business)
    get edit_business_category_path(business, category)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Office expense")
    expect(response.body).to include("category[archived]")
  end

  it "forbids viewers from accessing new form" do
    sign_in_as user_with_role("viewer", business)
    get new_business_category_path(business)
    expect(response).to have_http_status(:forbidden)
  end

  it "forbids viewers from accessing edit form" do
    sign_in_as user_with_role("viewer", business)
    get edit_business_category_path(business, category)
    expect(response).to have_http_status(:forbidden)
  end

  it "lets editors update name, line, and deductible percent" do
    sign_in_as user_with_role("editor", business)
    patch business_category_path(business, category), params: { category: { name: "Office supplies", schedule_c_line: "22", deductible_percent: "75" } }
    expect(response).to redirect_to(business_categories_path(business))
    category.reload
    expect(category.name).to eq("Office supplies")
    expect(category.schedule_c_line).to eq("22")
    expect(category.deductible_bps).to eq(7500)
  end

  it "lets editors un-archive" do
    archived_category = create(:category, business: business, archived_at: 1.day.ago)
    sign_in_as user_with_role("editor", business)
    patch business_category_path(business, archived_category), params: { category: { archived: "0" } }
    expect(archived_category.reload.archived_at).to be_nil
  end

  it "returns not found for category from another business" do
    other_category = create(:category)
    sign_in_as user_with_role("editor", business)
    get edit_business_category_path(business, other_category)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects invalid deductible percent with error message and value" do
    sign_in_as user_with_role("editor", business)
    post business_categories_path(business), params: { category: { name: "Test", kind: "expense", schedule_c_line: "18", deductible_percent: "half" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("half")
    expect(response.body).to include("is not a number")
  end

  it "offers sales tax treatment and the remittance kind only when the business collects sales tax" do
    business = create(:business)
    sign_in_as user_with_role("editor", business)
    get new_business_category_path(business)
    expect(response.body).not_to include("Sales tax treatment")
    create(:sales_tax_profile, business: business)
    get new_business_category_path(business)
    expect(response.body).to include("Sales tax treatment", "sales_tax_remittance")
    post business_categories_path(business), params: { category: { name: "Consulting", kind: "income", schedule_c_line: "1", sales_tax_treatment: "exempt" } }
    expect(business.categories.find_by!(name: "Consulting").sales_tax_treatment).to eq("exempt")
    get business_categories_path(business)
    expect(response.body).to include("Exempt sales")
  end

  it "saves an income category with the blank Default treatment as the derived default (taxable on line 1)" do
    business = create(:business)
    create(:sales_tax_profile, business: business)
    sign_in_as user_with_role("editor", business)
    post business_categories_path(business), params: { category: { name: "Retainers", kind: "income", schedule_c_line: "1", sales_tax_treatment: "" } }
    expect(response).to redirect_to(business_categories_path(business))
    expect(business.categories.find_by!(name: "Retainers").sales_tax_treatment).to eq("taxable")
  end
end
