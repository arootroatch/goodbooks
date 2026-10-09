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
end
