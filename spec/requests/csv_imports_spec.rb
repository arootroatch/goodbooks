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

  it "stores the saved mapping on the import as well as the account" do
    sign_in_as user_with_role("editor", business)
    post business_account_csv_imports_path(business, account), params: { csv_import: { file: fixture } }
    import = account.csv_imports.sole
    patch business_account_csv_import_mapping_path(business, account, import),
      params: { csv_import_mapping: { date_column: "Date", payee_column: "Description", amount_column: "Amount", date_format: "MM/DD/YYYY" } }
    expect(import.reload.mapping).to include("date_column" => "Date", "payee_column" => "Description")
    expect(import.mapping).to eq(account.reload.csv_mapping)
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

  it "rejects a non-file csv_import[file] param without creating an import" do
    sign_in_as user_with_role("editor", business)
    expect {
      post business_account_csv_imports_path(business, account), params: { csv_import: { file: "not a file" } }
    }.not_to change(CsvImport, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "has no public Active Storage direct upload route" do
    post "/rails/active_storage/direct_uploads"
    expect(response).to have_http_status(:not_found)
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

    it "re-checks the status under the lock when discarding a stale import" do
      sign_in_as editor
      allow_any_instance_of(CsvImport).to receive(:with_lock).and_wrap_original do |original, *args, &block|
        CsvImport.where(id: import.id).update_all(status: "committed")
        original.call(*args, &block)
      end
      delete business_account_csv_import_path(business, mapped, import)
      expect(import.reload).to be_committed
      expect(import.file).to be_attached
      expect(response).to redirect_to(business_account_csv_import_path(business, mapped, import))
      expect(flash[:alert]).to eq("This import was already committed.")
    end

    it "discards a previewed import and purges the file" do
      sign_in_as editor
      delete business_account_csv_import_path(business, mapped, import)
      expect(import.reload).to be_discarded
      expect(import.file).not_to be_attached
    end

    it "notes when the file was read as Windows-1252" do
      sign_in_as editor
      latin = Rack::Test::UploadedFile.new(StringIO.new("Date,Description,Amount\n01/05/2026,Caf\xE9,-3.00\n".b), "text/csv", original_filename: "latin.csv")
      legacy = mapped.csv_imports.create!(file: latin)
      get business_account_csv_import_path(business, mapped, legacy)
      expect(response.body).to include("This file wasn't UTF-8; it was read as Windows-1252 — check names and accents in the preview.")
      expect(response.body).to include("Café")
    end

    it "does not show the encoding note for UTF-8 files" do
      sign_in_as editor
      get business_account_csv_import_path(business, mapped, import)
      expect(response.body).not_to include("Windows-1252")
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

  it "says how many rows were already synced from the bank" do
    sign_in_as user_with_role("editor", business)
    plaid_account = create(:account, :plaid, business: business, csv_mapping: CsvImport::Mapping.new(
      date_column: "Date", payee_column: "Description", amount_column: "Amount", date_format: "MM/DD/YYYY"
    ).to_h)
    create(:transaction, account: plaid_account, posted_on: Date.new(2026, 10, 1), amount_cents: -8215, payee: "Kroger", plaid_transaction_id: "p-1")
    upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/plaid_overlap.csv"), "text/csv")
    csv_import = plaid_account.csv_imports.create!(file: upload)
    get business_account_csv_import_path(business, plaid_account, csv_import)
    expect(response.body).to include("1 already synced from the bank", "Already synced from bank")
    post commit_business_account_csv_import_path(business, plaid_account, csv_import)
    expect(flash[:notice]).to include("1 already synced from the bank")
  end
end
