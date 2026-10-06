require "rails_helper"

RSpec.describe TransactionFilter do
  let(:account) { create(:account) }
  let(:category) { create(:category, business: account.business) }
  let!(:jan) { create(:transaction, account: account, posted_on: Date.new(2026, 1, 1), payee: "Adobe", category: category) }
  let!(:dec) { create(:transaction, account: account, posted_on: Date.new(2026, 12, 31), payee: "Coffee", memo: "client mtg") }
  let(:scope) { Transaction.all }

  it "includes both ends of the date range" do
    results = TransactionFilter.new(scope, from: "2026-01-01", to: "2026-12-31").results
    expect(results).to contain_exactly(jan, dec)
  end

  it "ignores unparseable dates" do
    expect(TransactionFilter.new(scope, from: "garbage").results.count).to eq(2)
  end

  it "filters inbox, category, account, and text in payee or memo" do
    expect(TransactionFilter.new(scope, status: "inbox").results).to contain_exactly(dec)
    expect(TransactionFilter.new(scope, category_id: category.id.to_s).results).to contain_exactly(jan)
    expect(TransactionFilter.new(scope, q: "CLIENT").results).to contain_exactly(dec)
    expect(TransactionFilter.new(scope, q: "100%").results).to be_empty
    expect(TransactionFilter.new(scope, account_id: account.id.to_s).results.count).to eq(2)
  end

  it "orders newest first and paginates" do
    expect(TransactionFilter.new(scope, {}).results.first).to eq(dec)
    stub_const("TransactionFilter::PER_PAGE", 1)
    filter = TransactionFilter.new(scope, page: "1")
    expect(filter.results.to_a).to eq([ dec ])
    expect(filter.next_page?).to be(true)
    expect(TransactionFilter.new(scope, page: "2").next_page?).to be(false)
  end

  it "clamps page to 1..10000" do
    filter = TransactionFilter.new(scope, page: "99999999999999999999")
    expect(filter.page).to eq(10_000)
    expect(filter.results).to be_empty
    expect { filter.results }.not_to raise_error
  end

  it "treats non-numeric page as 1" do
    filter = TransactionFilter.new(scope, page: "abc")
    expect(filter.page).to eq(1)
  end
end
