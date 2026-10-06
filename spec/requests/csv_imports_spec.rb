require "rails_helper"

RSpec.describe "CSV imports" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, :csv, business: business) }
  let(:fixture) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/checking.csv"), "text/csv") }

  it "sends an unmapped account to the mapping step" do
    sign_in_as user_with_role("editor", business)
    post business_account_csv_imports_path(business, account), params: { csv_import: { file: fixture } }
    import = account.csv_imports.sole
    expect(response).to redirect_to(edit_business_account_csv_import_mapping_path(business, account, import))
  end

  it "re-renders the mapping with errors" do
    sign_in_as user_with_role("editor", business)
    post business_account_csv_imports_path(business, account), params: { csv_import: { file: fixture } }
    import = account.csv_imports.sole
    patch business_account_csv_import_mapping_path(business, account, import),
      params: { csv_import_mapping: { date_column: "Date", payee_column: "", amount_column: "Amount", date_format: "MM/DD/YYYY" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "shows a readable error for a broken file" do
    account.update!(csv_mapping: CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount").to_h)
    sign_in_as user_with_role("editor", business)
    bad = Rack::Test::UploadedFile.new(StringIO.new("Date,Nope\n1,2\n"), "text/csv", original_filename: "bad.csv")
    post business_account_csv_imports_path(business, account), params: { csv_import: { file: bad } }
    follow_redirect!
    expect(response.body).to include("Column not found: Description, Amount")
  end

  it "forbids viewers" do
    sign_in_as user_with_role("viewer", business)
    get new_business_account_csv_import_path(business, account)
    expect(response).to have_http_status(:forbidden)
    post business_account_csv_imports_path(business, account), params: { csv_import: { file: fixture } }
    expect(response).to have_http_status(:forbidden)
  end

  it "is not found for manual accounts" do
    cash = create(:account, business: business, source: "manual")
    sign_in_as user_with_role("editor", business)
    get new_business_account_csv_import_path(business, cash)
    expect(response).to have_http_status(:not_found)
  end
end
