require "rails_helper"

RSpec.describe PlaidFeed::Assignment do
  let!(:user) { create(:user) }
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:personal) { create(:business, :personal) }
  let!(:item) { create(:plaid_item, created_by: user) }
  let(:plaid_accounts) { FakePlaidGateway::DEFAULT_ACCOUNTS }

  before do
    create(:membership, user: user, business: business, role: "owner")
    create(:membership, user: user, business: personal, role: "owner")
  end

  def assign(*rows) = described_class.call(item: item, user: user, plaid_accounts: plaid_accounts, rows: rows)

  it "creates new accounts in owned books, inferring the kind" do
    result = assign({ plaid_account: "fake-checking", choice: "new", book: business.id.to_s, name: "Operating" },
                    { plaid_account: "fake-card", choice: "new", book: business.id.to_s, name: "" },
                    { plaid_account: "fake-savings", choice: "new", book: personal.id.to_s, name: "Rainy day" })
    expect(result).to be_ok
    operating = business.accounts.find_by!(name: "Operating")
    expect(operating).to have_attributes(source: "plaid", kind: "checking", plaid_item: item, plaid_account_id: "fake-checking",
                                         plaid_mask: "0000", plaid_name: "Plaid Checking", plaid_sync_from: nil)
    expect(business.accounts.find_by!(name: "Plaid Credit Card").kind).to eq("credit")
    expect(personal.accounts.find_by!(name: "Rainy day").kind).to eq("savings")
  end

  it "attaches an existing CSV account, defaulting sync-from to its latest transaction" do
    csv = create(:account, :csv, business: personal, name: "Joint Checking")
    create(:transaction, account: csv, posted_on: Date.new(2026, 9, 30), external_id: "h1")
    create(:transaction, account: csv, posted_on: Date.new(2026, 9, 12), external_id: "h2")
    expect(assign({ plaid_account: "fake-checking", choice: "attach", target: csv.id.to_s, sync_from: "" })).to be_ok
    expect(csv.reload).to have_attributes(source: "plaid", plaid_account_id: "fake-checking", plaid_sync_from: Date.new(2026, 9, 30))
  end

  it "rejects the same bank account appearing twice, applying nothing" do
    result = assign({ plaid_account: "fake-checking", choice: "new", book: business.id.to_s, name: "A" },
                    { plaid_account: "fake-checking", choice: "new", book: business.id.to_s, name: "B" })
    expect(result).not_to be_ok
    expect(result.errors["fake-checking"]).to eq("This bank account appears twice.")
    expect(Account.where(plaid_account_id: "fake-checking")).to be_empty
  end

  it "uses an entered sync-from date and rejects a bad one" do
    csv = create(:account, :csv, business: business)
    expect(assign({ plaid_account: "fake-checking", choice: "attach", target: csv.id.to_s, sync_from: "2000-01-01" })).to be_ok
    expect(csv.reload.plaid_sync_from).to eq(Date.new(2000, 1, 1))
    other = create(:account, :csv, business: business)
    result = assign({ plaid_account: "fake-card", choice: "attach", target: other.id.to_s, sync_from: "13/45/2026" })
    expect(result.errors).to eq("fake-card" => "Sync from is not a valid date")
    expect(other.reload.source).to eq("csv")
  end

  it "skips accounts and ignores rows for accounts already assigned" do
    create(:account, :plaid, business: business, plaid_item: item, plaid_account_id: "fake-checking")
    expect(assign({ plaid_account: "fake-checking", choice: "new", book: business.id.to_s },
                  { plaid_account: "fake-card", choice: "skip" })).to be_ok
    expect(Account.where(plaid_account_id: "fake-checking").count).to eq(1)
    expect(Account.where(plaid_account_id: "fake-card")).to be_empty
  end

  it "rejects books and accounts the user doesn't own, and applies nothing when any row fails" do
    edited = create(:business)
    create(:membership, user: user, business: edited, role: "editor")
    theirs = create(:account, :csv, business: edited)
    linked = create(:account, :plaid, business: business)
    archived = create(:account, :csv, business: business, archived_at: Time.current)
    result = assign({ plaid_account: "fake-checking", choice: "new", book: business.id.to_s },
                    { plaid_account: "fake-savings", choice: "new", book: edited.id.to_s },
                    { plaid_account: "fake-card", choice: "attach", target: theirs.id.to_s })
    expect(result.errors).to eq("fake-savings" => "Choose a book you own",
                                "fake-card" => "Choose an existing manual or CSV account in a book you own")
    expect(Account.where(plaid_account_id: "fake-checking")).to be_empty
    [ linked, archived ].each do |target|
      expect(assign({ plaid_account: "fake-card", choice: "attach", target: target.id.to_s })).not_to be_ok
    end
  end

  it "rejects unknown Plaid accounts and choices" do
    expect(assign({ plaid_account: "not-in-this-item", choice: "new", book: business.id.to_s }).errors)
      .to eq("not-in-this-item" => "That account isn't part of this connection")
    expect(assign({ plaid_account: "fake-card", choice: "merge" }).errors).to eq("fake-card" => "Choose skip, new account, or existing account")
  end

  it "maps Plaid types to account kinds" do
    expect(described_class.kind_for("depository", "checking")).to eq("checking")
    expect(described_class.kind_for("depository", "savings")).to eq("savings")
    expect(described_class.kind_for("depository", "cd")).to eq("other")
    expect(described_class.kind_for("credit", "credit card")).to eq("credit")
    expect(described_class.kind_for("loan", "mortgage")).to eq("other")
  end
end
