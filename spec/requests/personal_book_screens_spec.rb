require "rails_helper"

RSpec.describe "Personal book screens" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:book) { PersonalBookProvisioner.call(household) }

  before { sign_in_as owner }

  it "404s every business-only screen" do
    paths = [
      business_clients_path(book), business_invoices_path(book), new_business_invoice_path(book),
      business_mileage_entries_path(book), business_mileage_log_path(book), business_schedule_c_path(book),
      business_profit_and_loss_path(book), business_invoice_aging_path(book)
    ]
    paths.each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
    end
  end

  it "shows the shared screens with personal wording" do
    get business_path(book)
    expect(response.body).to include("Personal")
    expect(response.body).not_to include("Taxpayer", business_mileage_entries_path(book), business_invoices_path(book), business_schedule_c_path(book))
    [ business_accounts_path(book), business_transactions_path(book), business_rules_path(book), business_inbox_path(book) ].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
    end
  end

  it "lists categories with tithe labels instead of Schedule C" do
    get business_categories_path(book)
    expect(response.body).to include("Tithe payment", "Not tithable", "Tithable")
    expect(response.body).not_to include("Line ")
  end

  it "creates personal categories with tithe flags and no Schedule C line" do
    post business_categories_path(book), params: { category: { name: "Mission trip", kind: "expense", tithable: "0", tithe: "1" } }
    expect(response).to redirect_to(business_categories_path(book))
    category = book.categories.find_by!(name: "Mission trip")
    expect(category).to be_tithe
    expect(category.schedule_c_line).to be_nil
    get new_business_category_path(book)
    expect(response.body).to include("category[tithe]")
    expect(response.body).not_to include("category[schedule_c_line]")
  end

  it "rejects a crafted tithe flag on a business category" do
    business = create(:business)
    create(:membership, user: owner, business: business, role: "owner")
    post business_categories_path(business), params: { category: { name: "X", kind: "expense", schedule_c_line: "18", tithe: "1" } }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
