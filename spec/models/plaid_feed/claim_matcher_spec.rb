require "rails_helper"

RSpec.describe PlaidFeed::ClaimMatcher do
  def item(key, date, cents) = described_class::Item.new(key: key, posted_on: Date.parse(date), amount_cents: cents)
  def match(incoming, candidates) = described_class.call(incoming: incoming, candidates: candidates)

  it "pairs the same amount on the same day" do
    expect(match([ item("p1", "2026-10-05", -500) ], [ item(7, "2026-10-05", -500) ])).to eq("p1" => 7)
  end

  it "pairs up to three days apart in either direction, but not four" do
    expect(match([ item("p1", "2026-10-05", -500) ], [ item(7, "2026-10-08", -500) ])).to eq("p1" => 7)
    expect(match([ item("p1", "2026-10-05", -500) ], [ item(7, "2026-10-02", -500) ])).to eq("p1" => 7)
    expect(match([ item("p1", "2026-10-05", -500) ], [ item(7, "2026-10-09", -500) ])).to eq({})
  end

  it "never pairs different amounts or signs" do
    expect(match([ item("p1", "2026-10-05", -500) ], [ item(7, "2026-10-05", -501), item(8, "2026-10-05", 500) ])).to eq({})
  end

  it "prefers the nearest date, then the lowest id" do
    candidates = [ item(9, "2026-10-06", -500), item(8, "2026-10-04", -500), item(3, "2026-10-07", -500) ]
    expect(match([ item("p1", "2026-10-05", -500) ], candidates)).to eq("p1" => 8)
  end

  it "uses each candidate once, so two identical coffees pair one-to-one" do
    incoming = [ item("p1", "2026-10-05", -500), item("p2", "2026-10-06", -500) ]
    expect(match(incoming, [ item(7, "2026-10-05", -500) ])).to eq("p1" => 7)
    expect(match(incoming, [ item(7, "2026-10-05", -500), item(8, "2026-10-06", -500) ])).to eq("p1" => 7, "p2" => 8)
  end

  it "gives the closer incoming row the candidate when two compete" do
    incoming = [ item("far", "2026-10-02", -500), item("near", "2026-10-05", -500) ]
    expect(match(incoming, [ item(7, "2026-10-05", -500) ])).to eq("near" => 7)
  end

  it "handles empty inputs" do
    expect(match([], [ item(7, "2026-10-05", -500) ])).to eq({})
    expect(match([ item("p1", "2026-10-05", -500) ], [])).to eq({})
  end

  describe ".pair_records" do
    let(:account) { create(:account) }
    let(:row_class) { Data.define(:plaid_transaction_id, :posted_on, :amount_cents) }

    def row(id, date, cents) = row_class.new(plaid_transaction_id: id, posted_on: Date.parse(date), amount_cents: cents)

    it "maps each incoming key to the claimed record, within the date window and the given relation" do
      near = create(:transaction, account: account, posted_on: Date.new(2026, 10, 6), amount_cents: -500)
      create(:transaction, account: account, posted_on: Date.new(2026, 10, 20), amount_cents: -500)
      result = described_class.pair_records([ row("p1", "2026-10-05", -500) ], account.transactions, key: :plaid_transaction_id)
      expect(result).to eq("p1" => near)
    end

    it "only considers the relation it is given" do
      create(:transaction, account: account, posted_on: Date.new(2026, 10, 5), amount_cents: -500, external_id: "h")
      relation = account.transactions.where(external_id: nil)
      expect(described_class.pair_records([ row("p1", "2026-10-05", -500) ], relation, key: :plaid_transaction_id)).to eq({})
    end

    it "returns an empty hash for no rows" do
      expect(described_class.pair_records([], account.transactions, key: :plaid_transaction_id)).to eq({})
    end
  end
end
