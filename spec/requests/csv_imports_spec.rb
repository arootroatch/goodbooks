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

  context "with a mapped account and an uploaded import" do
    let(:mapping) { CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount").to_h }
    let!(:mapped) { create(:account, :csv, business: business, csv_mapping: mapping) }
    let!(:import) { mapped.csv_imports.create!(file: fixture) }
    let(:editor) { user_with_role("editor", business) }

    it "commits once and refuses a second commit" do
      sign_in_as editor
      post commit_business_account_csv_import_path(business, mapped, import)
      expect(response).to redirect_to(business_transactions_path(business, account_id: mapped.id))
      expect(flash[:notice]).to start_with("Imported 4 new transactions")
      post commit_business_account_csv_import_path(business, mapped, import)
      expect(response).to redirect_to(business_account_csv_import_path(business, mapped, import))
      expect(flash[:alert]).to include("already committed")
      expect(mapped.transactions.count).to eq(4)
    end

    it "does not discard a committed import" do
      sign_in_as editor
      import.commit!
      delete business_account_csv_import_path(business, mapped, import)
      expect(response).to redirect_to(business_account_csv_import_path(business, mapped, import))
      expect(flash[:alert]).to include("already committed")
      expect(import.reload).to be_committed
      expect(import.file).to be_attached
    end

    it "discards a previewed import and purges the file" do
      sign_in_as editor
      delete business_account_csv_import_path(business, mapped, import)
      expect(import.reload).to be_discarded
      expect(import.file).not_to be_attached
    end

    it "forbids viewers from committing and discarding" do
      sign_in_as user_with_role("viewer", business)
      post commit_business_account_csv_import_path(business, mapped, import)
      expect(response).to have_http_status(:forbidden)
      delete business_account_csv_import_path(business, mapped, import)
      expect(response).to have_http_status(:forbidden)
    end

    it "is not found for non-members" do
      sign_in_as create(:user)
      get business_account_csv_import_path(business, mapped, import)
      expect(response).to have_http_status(:not_found)
    end

    it "shows a discarded import without reading the file" do
      sign_in_as editor
      import.update!(status: "discarded")
      import.file.purge
      get business_account_csv_import_path(business, mapped, import)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This import was discarded")
    end

    it "redirects the mapping step for a committed import" do
      sign_in_as editor
      import.commit!
      get edit_business_account_csv_import_mapping_path(business, mapped, import)
      expect(response).to redirect_to(business_account_csv_import_path(business, mapped, import))
    end

    it "is not found for archived accounts" do
      mapped.update!(archived_at: Time.current)
      sign_in_as editor
      get new_business_account_csv_import_path(business, mapped)
      expect(response).to have_http_status(:not_found)
    end
  end
end
