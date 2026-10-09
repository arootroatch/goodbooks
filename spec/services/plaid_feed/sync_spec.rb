require "rails_helper"

RSpec.describe PlaidFeed::Sync do
  let!(:book) { create(:business) }
  let!(:item) { create(:plaid_item, access_token: "access-1") }
  let!(:checking) { create(:account, :plaid, business: book, plaid_item: item, plaid_account_id: "acc-checking", name: "Checking") }

  def plaid(id, amount:, date:, name: "COFFEE SHOP", merchant_name: nil, pending: false, account_id: "acc-checking")
    FakePlaidGateway.plaid_txn(id, account_id: account_id, amount: amount, date: Date.parse(date), name: name,
                                     merchant_name: merchant_name, pending: pending)
  end

  def page(**changes) = plaid_gateway.add_page("access-1", **changes)
  def sync = described_class.call(item.reload, gateway: plaid_gateway)

  it "inserts posted transactions with the app's sign, skips pending ones, and saves the cursor" do
    item.update!(status: "error", last_error: "old failure")
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01", name: "SQ *COFFEE 8475", merchant_name: "Coffee"),
                  plaid("t2", amount: 9.0, date: "2026-10-01", pending: true) ])
    result = sync
    txn = checking.transactions.sole
    expect(txn.attributes.slice("plaid_transaction_id", "posted_on", "amount_cents", "payee", "memo"))
      .to eq("plaid_transaction_id" => "t1", "posted_on" => Date.new(2026, 10, 1), "amount_cents" => -450,
             "payee" => "Coffee", "memo" => "SQ *COFFEE 8475")
    expect(result.inserted).to eq(1)
    expect(item.reload).to have_attributes(cursor: "page-1", status: "ok", last_error: nil)
    expect(item.last_synced_at).to be_present
  end

  it "skips transactions before the account's sync-from date" do
    checking.update!(plaid_sync_from: Date.new(2026, 10, 2))
    page(added: [ plaid("old", amount: 1.0, date: "2026-10-01"), plaid("new", amount: 2.0, date: "2026-10-02") ])
    sync
    expect(checking.transactions.pluck(:plaid_transaction_id)).to eq([ "new" ])
  end

  it "ignores Plaid accounts that aren't assigned" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01", account_id: "acc-unassigned") ])
    expect(sync.inserted).to eq(0)
    expect(Transaction.count).to eq(0)
  end

  it "claims a matching CSV row instead of inserting a duplicate, leaving the user's version alone" do
    software = create(:category, business: book, name: "Software")
    csv = create(:transaction, account: checking, posted_on: Date.new(2026, 10, 2), amount_cents: -450, payee: "SQ *COFFEE 123",
                               external_id: "hash-1", category: software, categorized_by: "user")
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01", merchant_name: "Coffee") ])
    result = sync
    expect(checking.transactions.count).to eq(1)
    expect(csv.reload).to have_attributes(plaid_transaction_id: "t1", payee: "SQ *COFFEE 123", posted_on: Date.new(2026, 10, 2),
                                          category: software, external_id: "hash-1")
    expect(result.claimed).to eq(1)
  end

  it "claims a hand-entered row too" do
    manual = create(:transaction, account: checking, posted_on: Date.new(2026, 10, 1), amount_cents: -450, payee: "coffee")
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01") ])
    sync
    expect(manual.reload.plaid_transaction_id).to eq("t1")
  end

  it "claims one-to-one: two identical coffees and one CSV row make two rows, and re-delivery adds nothing" do
    csv = create(:transaction, account: checking, posted_on: Date.new(2026, 10, 1), amount_cents: -500, payee: "COFFEE", external_id: "h")
    page(added: [ plaid("t1", amount: 5.0, date: "2026-10-01"), plaid("t2", amount: 5.0, date: "2026-10-02") ])
    sync
    expect(csv.reload.plaid_transaction_id).to eq("t1")
    expect(checking.transactions.pluck(:plaid_transaction_id)).to contain_exactly("t1", "t2")
    page(added: [ plaid("t2", amount: 5.0, date: "2026-10-02") ])
    sync
    expect(checking.transactions.count).to eq(2)
  end

  it "applies bank modifications to date and amount, but never the payee or memo" do
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01", name: "PENDING NAME") ])
    sync
    checking.transactions.sole.update!(memo: "my note", payee: "My payee")
    page(modified: [ plaid("t1", amount: 5.25, date: "2026-10-03", name: "FINAL NAME") ])
    expect(sync.modified).to eq(1)
    expect(checking.transactions.sole).to have_attributes(posted_on: Date.new(2026, 10, 3), amount_cents: -525, payee: "My payee",
                                                          memo: "my note")
  end

  it "keeps the hand-typed payee of a claimed row when the bank modifies it" do
    manual = create(:transaction, account: checking, posted_on: Date.new(2026, 10, 1), amount_cents: -450, payee: "coffee")
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01", name: "SQ *COFFEE 8475") ])
    sync
    expect(manual.reload.plaid_transaction_id).to eq("t1")
    page(modified: [ plaid("t1", amount: 4.75, date: "2026-10-02", name: "SQ *COFFEE FINAL") ])
    sync
    expect(manual.reload).to have_attributes(payee: "coffee", amount_cents: -475, posted_on: Date.new(2026, 10, 2))
  end

  it "ignores modifications to an excluded row" do
    page(added: [ plaid("t1", amount: 4.5, date: "2026-10-01") ])
    sync
    checking.transactions.sole.update!(excluded: true)
    page(modified: [ plaid("t1", amount: 99.0, date: "2026-10-01") ])
    sync
    expect(checking.transactions.sole.amount_cents).to eq(-450)
  end

  it "flags a modification the app's rules reject, keeping the user's version" do
    income = create(:category, :income, business: book, name: "Sales")
    page(added: [ plaid("d1", amount: -1200.0, date: "2026-10-01", name: "ACME PAYMENT") ])
    sync
    deposit = checking.transactions.sole
    deposit.update!(category: income, categorized_by: "user")
    invoice = create(:invoice, business: book, amount_cents: 120_000)
    expect(InvoicePayments.link(invoice: invoice, deposit: deposit)).to be_ok
    page(modified: [ plaid("d1", amount: -1000.0, date: "2026-10-01", name: "ACME PAYMENT") ])
    result = sync
    expect(result.flagged).to eq(1)
    expect(deposit.reload).to have_attributes(amount_cents: 120_000, review_reason: "changed_by_bank")
    expect(invoice.reload).to be_paid
  end

  describe "removals" do
    let!(:category) { create(:category, business: book) }

    before do
      page(added: %w[a b c d].map { plaid(_1, amount: 1.0, date: "2026-10-01") })
      sync
    end

    def row(id) = checking.transactions.find_by!(plaid_transaction_id: id)

    it "excludes untouched and rule-categorized rows, and flags rows the user categorized or linked" do
      rule = create(:rule, business: book, category: category)
      row("b").update!(category: category, categorized_by: "rule", rule: rule)
      row("c").update!(category: category, categorized_by: "user")
      income = create(:category, :income, business: book)
      row("d").update!(amount_cents: 120_000, category: income, categorized_by: "rule", rule: rule)
      expect(InvoicePayments.link(invoice: create(:invoice, business: book, amount_cents: 120_000), deposit: row("d"))).to be_ok
      page(removed: %w[a b c d x].map { { transaction_id: _1, account_id: "acc-checking" } })
      result = sync
      expect(row("a")).to have_attributes(excluded: true, review_reason: nil)
      expect(row("b")).to have_attributes(excluded: true, review_reason: nil)
      expect(row("c")).to have_attributes(excluded: false, review_reason: "removed_by_bank")
      expect(row("d")).to have_attributes(excluded: false, review_reason: "removed_by_bank")
      expect(result).to have_attributes(excluded: 2, flagged: 2)
    end
  end

  it "runs each book's rules on inserted rows only" do
    personal = create(:business, :personal)
    joint = create(:account, :plaid, business: personal, plaid_item: item, plaid_account_id: "acc-joint")
    software = create(:category, business: book, name: "Software")
    groceries = create(:category, business: personal, name: "Groceries")
    create(:rule, business: book, value: "adobe", category: software)
    create(:rule, business: personal, value: "kroger", category: groceries)
    claimed = create(:transaction, account: checking, posted_on: Date.new(2026, 10, 1), amount_cents: -5499, payee: "ADOBE OLD",
                                   external_id: "h")
    page(added: [ plaid("t1", amount: 54.99, date: "2026-10-01", name: "ADOBE"), plaid("t2", amount: 20.0, date: "2026-10-01", name: "ADOBE CC"),
                  plaid("t3", amount: 80.0, date: "2026-10-01", name: "KROGER", account_id: "acc-joint") ])
    sync
    expect(claimed.reload.category).to be_nil
    expect(checking.transactions.find_by!(plaid_transaction_id: "t2")).to have_attributes(category: software, categorized_by: "rule")
    expect(joint.transactions.sole).to have_attributes(category: groceries, categorized_by: "rule")
  end

  it "does not run rules on a row the same sync excluded" do
    software = create(:category, business: book, name: "Software")
    create(:rule, business: book, value: "adobe", category: software)
    page(added: [ plaid("t1", amount: 5.0, date: "2026-10-01", name: "ADOBE") ],
         removed: [ { transaction_id: "t1", account_id: "acc-checking" } ])
    sync
    expect(checking.transactions.sole).to have_attributes(excluded: true, category: nil)
  end

  it "follows pagination to the last page" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01") ])
    page(added: [ plaid("t2", amount: 2.0, date: "2026-10-01") ])
    sync
    expect(checking.transactions.count).to eq(2)
    expect(item.reload.cursor).to eq("page-2")
  end

  it "restarts from the saved cursor when Plaid's data changes mid-sync" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01") ])
    plaid_gateway.fail_next(:transactions_sync, PlaidGateway::MutationDuringPagination.new("changed"))
    sync
    expect(checking.transactions.count).to eq(1)
    expect(plaid_gateway.calls.count(:transactions_sync)).to eq(2)
  end

  it "gives up as a transient error after three restarts, writing nothing" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01") ])
    4.times { plaid_gateway.fail_next(:transactions_sync, PlaidGateway::MutationDuringPagination.new("changed")) }
    expect { sync }.to raise_error(PlaidGateway::TransientError)
    expect(Transaction.count).to eq(0)
    expect(item.reload.cursor).to be_nil
  end

  it "writes nothing and keeps the cursor when a page can't be applied" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01"), plaid("t2", amount: 12.345, date: "2026-10-01") ])
    expect { sync }.to raise_error(PlaidFeed::TransactionMapper::InvalidAmount)
    expect(Transaction.count).to eq(0)
    expect(item.reload.cursor).to be_nil
  end

  it "aborts as an error, writing nothing, when an amount is missing" do
    page(added: [ plaid("t1", amount: 1.0, date: "2026-10-01"), plaid("t2", amount: nil, date: "2026-10-01") ])
    expect { sync }.to raise_error(ArgumentError)
    expect(Transaction.count).to eq(0)
    expect(item.reload.cursor).to be_nil
  end
end
