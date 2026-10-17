# spec/models/audit_call_sites_spec.rb
require "rails_helper"

RSpec.describe "Audit summary call sites" do
  let(:business) { create(:business) }
  let(:actor) { create(:user, :household_owner) }

  it "creating a book writes one summary" do
    business
    actor
    book = Audit.as(actor) { BusinessProvisioner.call(Household.first.businesses.new(name: "New Co", person: business.person), owner: actor) }
    expect(AuditEvent.pluck(:action, :summary, :business_id)).to eq([ [ "summary", "Created book New Co", book.id ] ])
  end

  it "creating the personal book writes one summary" do
    business
    actor
    Audit.as(actor) { PersonalBookProvisioner.call(business.household) }
    expect(AuditEvent.pluck(:summary)).to eq([ "Created the personal book" ])
  end

  it "syncing an existing personal book writes its membership events normally" do
    book = PersonalBookProvisioner.call(business.household)
    spouse = create(:user)
    create(:person, household: business.household, user: spouse)
    actor
    Audit.as(actor) { PersonalBookProvisioner.call(business.household) }
    expect(AuditEvent.where(auditable_type: "Membership", action: "create").count).to be >= 1
    expect(AuditEvent.where(action: "summary")).to be_empty
    expect(book).to be_personal
  end

  it "reordering rules and goals writes one summary each" do
    first, second = create_list(:rule, 2, business: business)
    actor
    Audit.as(actor) { second.move_to!(1) }
    goal_a = create(:goal, business: business)
    create(:goal, business: business)
    Audit.as(actor) { goal_a.move_to!(2) }
    expect(AuditEvent.pluck(:summary)).to eq([ "Reordered rules", "Reordered goals" ])
    expect(first.reload.position).to eq(2)
  end

  it "committing a CSV import writes one summary, including the rules it applied" do
    actor
    software = create(:category, business: business, name: "Software")
    create(:rule, business: business, value: "adobe", category: software)
    account = create(:account, :csv, business: business, name: "Checking",
      csv_mapping: CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount").to_h)
    import = account.csv_imports.create!(file: Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/checking.csv"), "text/csv"))
    Audit.as(actor) { import.commit! }
    expect(AuditEvent.pluck(:action)).to eq([ "summary" ])
    expect(AuditEvent.last.summary).to eq("Imported 4 transactions into Checking (0 duplicates skipped)")
  end

  it "Plaid sync writes no audit events" do
    item = create(:plaid_item, access_token: "access-1")
    create(:account, :plaid, plaid_item: item, plaid_account_id: "acc-1")
    plaid_gateway.add_page("access-1", added: [ FakePlaidGateway.plaid_txn("t1", account_id: "acc-1", amount: 1.0, date: Date.new(2026, 10, 1), name: "X") ])
    expect { PlaidSyncJob.perform_now(item) }.not_to change(AuditEvent, :count)
  end
end
