require "rails_helper"

RSpec.describe Account do
  it "needs a Plaid connection and account id when its source is plaid" do
    account = build(:account, source: "plaid")
    expect(account).not_to be_valid
    expect(account.errors[:source]).to include("plaid needs a Plaid connection")
    expect(build(:account, :plaid)).to be_valid
  end

  it "keeps Plaid link fields off non-Plaid accounts" do
    account = build(:account, :csv, plaid_item: create(:plaid_item), plaid_account_id: "acc-1")
    expect(account).not_to be_valid
    expect(account.errors[:source]).to include("must be plaid while linked to a Plaid connection")
  end

  it "links each Plaid account to one goodbooks account" do
    first = create(:account, :plaid)
    expect(build(:account, :plaid, plaid_account_id: first.plaid_account_id)).not_to be_valid
  end

  it "allows CSV upload on csv and plaid accounts only" do
    expect(build(:account, :csv)).to be_csv_importable
    expect(build(:account, :plaid)).to be_csv_importable
    expect(build(:account)).not_to be_csv_importable
    csv = create(:account, :csv)
    plaid = create(:account, :plaid)
    create(:account)
    expect(Account.csv_importable).to contain_exactly(csv, plaid)
  end

  it "detaches from Plaid back to a CSV account when it has a mapping, keeping its transactions" do
    account = create(:account, :plaid, plaid_mask: "0000", plaid_name: "Checking", plaid_sync_from: Date.new(2026, 1, 1),
                                       csv_mapping: { "date_column" => "Date" })
    txn = create(:transaction, account: account, plaid_transaction_id: "t1")
    account.detach_from_plaid!
    expect(account.reload).to have_attributes(source: "csv", plaid_item_id: nil, plaid_account_id: nil, plaid_mask: nil,
                                              plaid_name: nil, plaid_sync_from: nil)
    expect(txn.reload).to have_attributes(account_id: account.id, plaid_transaction_id: "t1")
  end

  it "detaches from Plaid back to a manual account without a mapping" do
    account = create(:account, :plaid)
    account.detach_from_plaid!
    expect(account.reload.source).to eq("manual")
  end
end
