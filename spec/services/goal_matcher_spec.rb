require "rails_helper"

RSpec.describe GoalMatcher do
  let(:book) { create(:business) }
  let(:account) { create(:account, business: book) }

  def txn(payee, cents = -100_00, **attrs) = create(:transaction, account: account, payee: payee, amount_cents: cents, **attrs)

  # Goals rematch when created (Task 4's callback), so each example creates its goals before the rows they should match.
  def goal(**attrs) = create(:goal, business: book, **attrs)

  it "links eligible outflows to the first matching active goal by position" do
    first = goal(match_value: "tony")
    second = goal(match_value: "tony russo")
    rows = [ txn("ZELLE TONY RUSSO"), txn("TONY RUSSO REFUND", 50_00), txn("KROGER"), txn("TONY", excluded: true) ]
    expect(described_class.new(book).apply(rows)).to eq(1)
    expect(rows.map { _1.reload.goal }).to eq([ first, nil, nil, nil ])
    expect(rows.first.goal_linked_by).to eq("matcher")
    expect(second.transactions).to be_empty
  end

  it "skips archived goals, goals without a matcher, and rows already linked or unlinked by hand" do
    goal(match_value: "tony", archived_at: Time.current)
    goal(match_field: nil, match_operator: nil, match_value: nil)
    hand_goal = goal(match_value: "zzz")
    rows = [ txn("TONY", goal: hand_goal, goal_linked_by: "user"), txn("TONY", goal_linked_by: "user"), txn("TONY") ]
    expect(described_class.new(book).apply(rows)).to eq(0)
    expect(rows.map { _1.reload.goal }).to eq([ hand_goal, nil, nil ])
  end

  it "respects the matcher's amount range against the absolute amount" do
    goal(match_value: "tony", match_amount_min: "1,000", match_amount_max: "2,000")
    rows = [ txn("TONY", -999_99), txn("TONY", -1_500_00), txn("TONY", -2_000_01) ]
    described_class.new(book).apply(rows)
    expect(rows.map { _1.reload.goal_id.present? }).to eq([ false, true, false ])
  end

  it "only touches goal columns, even on rows that would fail validation" do
    goal(match_value: "tony")
    row = txn("TONY")
    row.update_column(:sales_tax_period_starts_on, Date.new(1999, 1, 1))
    expect { described_class.new(book).apply([ row ]) }.not_to raise_error
    expect(row.reload.goal_linked_by).to eq("matcher")
  end

  describe "#rematch" do
    it "relinks every eligible row in the book, keeping hand links and archived goals' links" do
      old = goal(match_value: "tony")
      archived = goal(match_value: "tony")
      kept = txn("TONY OLD", goal: archived, goal_linked_by: "matcher")
      archived.update_column(:archived_at, Time.current)
      hand = txn("TONY HAND", goal: old, goal_linked_by: "user")
      auto = txn("TONY AUTO", goal: old, goal_linked_by: "matcher")
      fresh = txn("TONY NEW")
      other_book = create(:transaction, payee: "TONY")
      top = goal(match_value: "tony")
      top.update_column(:position, 0)
      expect(described_class.new(book).rematch).to eq(2)
      expect([ kept, hand, auto, fresh, other_book ].map { _1.reload.goal }).to eq([ archived, old, top, top, nil ])
    end
  end
end
