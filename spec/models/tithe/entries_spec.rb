require "rails_helper"

RSpec.describe Tithe::Entries do
  let(:book) { create(:business, :personal, tithe_start_on: Date.new(2026, 1, 4)) }
  let(:checking) { create(:account, business: book) }
  let(:savings) { create(:account, business: book) }
  let(:draws) { create(:category, :income, business: book, name: "Owner draws") }
  let(:refunds) { create(:category, :income, business: book, name: "Refunds", tithable: false) }
  let(:groceries) { create(:category, business: book, name: "Groceries") }
  let(:tithe) { create(:category, business: book, name: "Tithe", tithe: true) }

  def txn(cents, account: checking, on: Date.new(2026, 1, 6), **attrs)
    create(:transaction, account: account, amount_cents: cents, posted_on: on, **attrs)
  end

  def kinds = described_class.for(book).map { [ _1.kind, _1.cents ] }

  it "counts uncategorized deposits and tithable income across the book's accounts" do
    txn(10_000)
    txn(20_000, account: savings, category: draws)
    expect(kinds).to contain_exactly([ :income, 10_000 ], [ :income, 20_000 ])
  end

  it "skips not-tithable income, transfers, excluded rows, and days before the start date" do
    txn(5_000, category: refunds)
    txn(6_000, transfer: true)
    txn(7_000, excluded: true)
    txn(8_000, on: Date.new(2026, 1, 3))
    expect(kinds).to be_empty
  end

  it "never treats a positive amount in an expense category as income" do
    txn(2_500, category: groceries)
    expect(kinds).to be_empty
  end

  it "turns tithe-category rows into payments, with refunds negative" do
    check = txn(-30_000, category: tithe)
    txn(5_000, category: tithe)
    expect(kinds).to contain_exactly([ :payment, 30_000 ], [ :payment, -5_000 ])
    expect(described_class.for(book).find { _1.cents == 30_000 }.source).to eq(check)
  end

  it "ignores other books" do
    create(:transaction, amount_cents: 10_000, posted_on: Date.new(2026, 1, 6))
    expect(kinds).to be_empty
  end

  it "builds a ledger only when a start date is set" do
    txn(10_000)
    expect(Tithe.ledger_for(book, today: Date.new(2026, 1, 10)).owed_cents).to eq(1_000)
    book.update!(tithe_start_on: nil)
    expect(Tithe.ledger_for(book)).to be_nil
  end
end
