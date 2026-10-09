require "rails_helper"

RSpec.describe "CSV import on a Plaid-fed account" do
  let!(:account) do
    create(:account, :plaid, csv_mapping: CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount",
                                                                 date_format: "MM/DD/YYYY").to_h)
  end
  let!(:synced) { create(:transaction, account: account, posted_on: Date.new(2026, 10, 1), amount_cents: -8215, payee: "Kroger", plaid_transaction_id: "p-1") }

  def import
    upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/plaid_overlap.csv"), "text/csv")
    account.csv_imports.create!(file: upload)
  end

  it "previews a row Plaid already brought in as synced, next to its match" do
    preview = import.preview
    expect(preview.entries.map(&:status)).to eq(%i[synced new])
    expect(preview.synced_entries.sole.match).to eq(synced)
    expect(preview.new_entries.sole.row.payee).to eq("SHELL OIL 5551")
  end

  it "skips synced rows on commit, stamps them with the CSV hash, and treats a re-import as duplicates" do
    first = import
    first.commit!
    expect(account.transactions.count).to eq(2)
    expect(first.reload).to have_attributes(new_count: 1, synced_count: 1, duplicate_count: 0)
    expect(synced.reload.external_id).to be_present
    expect(synced.payee).to eq("Kroger")

    again = import
    expect(again.preview.entries.map(&:status)).to eq(%i[duplicate duplicate])
  end

  it "doesn't match a Plaid row that already carries a CSV hash" do
    synced.update!(external_id: "from-another-file")
    expect(import.preview.entries.map(&:status)).to eq(%i[new new])
  end
end
