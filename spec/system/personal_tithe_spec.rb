require "rails_helper"

RSpec.describe "Personal tithe" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:book) { PersonalBookProvisioner.call(household) }
  let!(:account) { create(:account, :csv, business: book, name: "Joint Checking") }
  let!(:rule) { create(:rule, business: book, value: "grace church", category: book.categories.find_by!(name: "Tithe")) }

  it "imports the joint account, recognizes the tithe check, and shows the balance" do
    system_sign_in_as owner
    visit business_accounts_path(book)
    click_on "Import CSV"
    attach_file "csv_import[file]", Rails.root.join("spec/fixtures/files/joint_checking.csv")
    click_on "Upload"
    select "Date", from: "Date column"
    select "Description", from: "Payee column"
    select "Amount", from: "Amount column"
    select "MM/DD/YYYY", from: "Date format"
    click_on "Save mapping"
    click_on "Import"
    expect(page).to have_content("Imported 3 new transactions")
    expect(account.transactions.find_by!(payee: "CHECK 1042 GRACE CHURCH").category.name).to eq("Tithe")

    visit business_tithe_path(book)
    fill_in "Track tithe from", with: "2026-01-04"
    click_on "Save"
    expect(page).to have_content("Behind $50.00")
  end
end
