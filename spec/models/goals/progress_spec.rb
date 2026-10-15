require "rails_helper"

RSpec.describe Goals::Progress do
  let(:book) { create(:business) }
  let(:savings) { create(:account, business: book, kind: "savings", opening_balance: "8,000", opening_balance_on: Date.new(2026, 1, 1)) }

  def savings_goal(name, target) = create(:goal, :savings, business: book, account: savings, name: name, target: target)
  def summary(rows) = rows.map { [ _1.goal.name, _1.saved_cents, _1.met?, _1.percent ] }

  it "fills savings goals on one account in priority order" do
    savings_goal("Nest egg", "6,000")
    savings_goal("Truck", "10,000")
    expect(summary(described_class.for_book(book))).to eq([ [ "Nest egg", 6_000_00, true, 100 ], [ "Truck", 2_000_00, false, 20 ] ])
  end

  it "takes withdrawals from the lowest priority first, and a reorder flips the allocation" do
    savings_goal("Nest egg", "6,000")
    truck = savings_goal("Truck", "10,000")
    create(:transaction, account: savings, posted_on: Date.new(2026, 2, 1), amount_cents: -500_00)
    expect(summary(described_class.for_book(book)).map(&:second)).to eq([ 6_000_00, 1_500_00 ])
    truck.move_to!(1)
    expect(summary(described_class.for_book(book))).to eq([ [ "Truck", 7_500_00, false, 75 ], [ "Nest egg", 0, false, 0 ] ])
  end

  it "fills nothing from a negative balance and flags an unknown one" do
    savings_goal("Nest egg", "6,000")
    create(:transaction, account: savings, posted_on: Date.new(2026, 2, 1), amount_cents: -9_000_00)
    expect(described_class.for_book(book).sole.saved_cents).to eq(0)

    plaid = create(:account, :plaid, business: book, kind: "savings")
    create(:goal, :savings, business: book, account: plaid)
    row = described_class.for_book(book).last
    expect(row).to be_balance_unknown
    expect(row).not_to be_met
  end

  it "sums payment goals' linked non-excluded outflows, net of refunds, never below zero" do
    goal = create(:goal, business: book, target: "1,000", match_field: nil, match_operator: nil, match_value: nil)
    account = create(:account, business: book)
    create(:transaction, account: account, amount_cents: -600_00, goal: goal, goal_linked_by: "user")
    create(:transaction, account: account, amount_cents: 100_00, goal: goal, goal_linked_by: "user")
    create(:transaction, account: account, amount_cents: -900_00, goal: goal, goal_linked_by: "user", excluded: true)
    row = described_class.for_book(book).sole
    expect([ row.saved_cents, row.percent, row.met? ]).to eq([ 500_00, 50, false ])

    refund_only = create(:goal, business: book, match_field: nil, match_operator: nil, match_value: nil)
    create(:transaction, account: account, amount_cents: 50_00, goal: refund_only, goal_linked_by: "user")
    expect(described_class.for_goals([ refund_only ]).sole.saved_cents).to eq(0)
  end

  it "caps percent at 100 and leaves archived goals out of the book" do
    goal = create(:goal, business: book, target: "100", match_field: nil, match_operator: nil, match_value: nil)
    create(:transaction, account: create(:account, business: book), amount_cents: -250_00, goal: goal, goal_linked_by: "user")
    expect(described_class.for_book(book).sole.percent).to eq(100)
    goal.update!(archived_at: Time.current)
    expect(described_class.for_book(book)).to be_empty
  end
end
