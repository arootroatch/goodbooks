require "rails_helper"

RSpec.describe CsvImport do
  let(:business) { create(:business) }
  let(:software) { create(:category, business: business, name: "Software") }
  let(:account) do
    create(:account, :csv, business: business,
      csv_mapping: CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount").to_h)
  end
  let(:fixture) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/checking.csv"), "text/csv") }

  def upload = account.csv_imports.create!(file: fixture)

  it "rejects files over 5 MB" do
    big = Rack::Test::UploadedFile.new(StringIO.new("a" * (CsvImport::MAX_BYTES + 1)), "text/csv", original_filename: "big.csv")
    import = account.csv_imports.new(file: big)
    expect(import).not_to be_valid
    expect(import.errors[:file]).to include("must be 5 MB or smaller")
  end

  it "requires a file" do
    expect(account.csv_imports.new).not_to be_valid
  end

  it "previews new rows with proposed rules" do
    create(:rule, business: business, value: "adobe", category: software)
    preview = upload.preview
    expect(preview.new_entries.size).to eq(4)
    expect(preview.new_entries.first.proposed_rule.category).to eq(software)
  end

  it "ignores rules with archived categories when proposing" do
    create(:rule, business: business, value: "adobe", category: software)
    software.update!(archived_at: Time.current)
    expect(upload.preview.new_entries.map(&:proposed_rule)).to all(be_nil)
  end

  it "commits new rows, applies rules, and records counts" do
    create(:rule, business: business, value: "adobe", category: software)
    import = upload
    import.commit!
    expect(account.transactions.count).to eq(4)
    expect(account.transactions.find_by!(payee: "ADOBE CREATIVE CLOUD").category).to eq(software)
    expect(import.reload).to be_committed
    expect([ import.row_count, import.new_count, import.duplicate_count, import.error_count ]).to eq([ 4, 4, 0, 0 ])
  end

  it "imports nothing new the second time" do
    upload.commit!
    second = upload
    expect(second.preview.duplicate_entries.size).to eq(4)
    second.commit!
    expect(account.transactions.count).to eq(4)
    expect(second.reload.new_count).to eq(0)
  end

  it "copies the account's mapping onto the import and parses with it after the account mapping changes" do
    import = upload
    expect(import.mapping).to eq(account.csv_mapping)
    original = import.preview.new_entries.map { _1.row.amount_cents }
    account.update!(csv_mapping: account.csv_mapping.merge("invert_sign" => true))
    import.commit!
    expect(account.transactions.order(:id).map(&:amount_cents)).to eq(original)
  end

  it "falls back to the account's mapping for legacy imports without one" do
    import = upload
    import.update_columns(mapping: nil)
    account.update!(csv_mapping: account.csv_mapping.merge("invert_sign" => true))
    expect(import.reload.preview.new_entries.first.row.amount_cents).to eq(5499)
  end

  it "refuses to commit twice" do
    import = upload
    import.commit!
    expect { import.commit! }.to raise_error(CsvImport::NotPreviewed)
  end

  it "refuses to commit a stale copy of an import committed elsewhere" do
    import = upload
    CsvImport.find(import.id).update_columns(status: "committed")
    expect { import.commit! }.to raise_error(CsvImport::NotPreviewed)
    expect(account.transactions.count).to eq(0)
  end
end
