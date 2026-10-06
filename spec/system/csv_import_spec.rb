require "rails_helper"

RSpec.describe "Importing a CSV statement" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, :csv, business: business, name: "Checking") }
  let!(:software) { create(:category, business: business, name: "Software", schedule_c_line: "27a") }
  let!(:rule) { create(:rule, business: business, value: "adobe", category: software) }
  let(:editor) { user_with_role("editor", business) }
  let(:csv_path) { Rails.root.join("spec/fixtures/files/checking.csv") }

  def upload
    visit business_accounts_path(business)
    click_on "Import CSV"
    attach_file "csv_import[file]", csv_path
    click_on "Upload"
  end

  it "maps, previews, commits, and skips duplicates on re-import" do
    system_sign_in_as editor
    upload

    select "Date", from: "Date column"
    select "Description", from: "Payee column"
    select "Amount", from: "Amount column"
    select "MM/DD/YYYY", from: "Date format"
    click_on "Save mapping"

    expect(page).to have_content("4 new")
    expect(page).to have_content("Software")
    click_on "Import"
    expect(page).to have_content("Imported 4 new transactions (0 duplicates skipped, 0 rows with errors).")
    expect(account.transactions.find_by!(payee: "ADOBE CREATIVE CLOUD").category).to eq(software)

    upload
    expect(page).to have_content("0 new")
    expect(page).to have_content("4 duplicates")
    click_on "Import"
    expect(account.transactions.count).to eq(4)
  end
end
