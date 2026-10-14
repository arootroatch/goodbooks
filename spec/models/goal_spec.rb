require "rails_helper"

RSpec.describe Goal do
  let(:book) { create(:business) }

  it "requires a name, a known kind and a positive target" do
    expect(build(:goal, business: book, name: "")).not_to be_valid
    expect(build(:goal, business: book, kind: "other")).not_to be_valid
    expect(build(:goal, business: book, target_cents: 0)).not_to be_valid
    expect(build(:goal, business: book, target: "abc")).not_to be_valid
  end

  it "accepts a payment goal with a full matcher or none at all, not a partial one" do
    expect(build(:goal, business: book)).to be_valid
    expect(build(:goal, business: book, match_field: nil, match_operator: nil, match_value: nil)).to be_valid
    expect(build(:goal, business: book, match_value: "")).not_to be_valid
    expect(build(:goal, business: book, match_operator: "regex")).not_to be_valid
    expect(build(:goal, business: book, match_amount_min: "50", match_amount_max: "10")).not_to be_valid
  end

  it "needs an active, non-credit account in the same book for savings" do
    expect(build(:goal, :savings, business: book)).to be_valid
    expect(build(:goal, :savings, business: book, account: nil)).not_to be_valid
    expect(build(:goal, :savings, business: book, account: create(:account))).not_to be_valid
    expect(build(:goal, :savings, business: book, account: create(:account, business: book, kind: "credit"))).not_to be_valid
    expect(build(:goal, :savings, business: book, account: create(:account, business: book, archived_at: Time.current))).not_to be_valid
  end

  it "lets a savings goal be updated after its account is archived" do
    goal = create(:goal, :savings, business: book)
    goal.account.update!(archived_at: Time.current)
    expect(goal.reload.update(name: "Renamed")).to be(true)
    expect(goal.update(archived_at: Time.current)).to be(true)
  end

  it "rejects retargeting a savings goal to an archived or credit account" do
    goal = create(:goal, :savings, business: book)
    expect(goal.update(account: create(:account, business: book, archived_at: Time.current))).to be(false)
    expect(goal.update(account: create(:account, business: book, kind: "credit"))).to be(false)
  end

  it "is removed when its book is destroyed" do
    create(:goal, :savings, business: book)
    expect { book.destroy }.to change(described_class, :count).by(-1)
    expect(Business.exists?(book.id)).to be(false)
  end

  it "clears fields that don't belong to its kind" do
    savings = create(:goal, :savings, business: book, match_value: "tony", match_field: "payee", match_operator: "contains")
    expect(savings.attributes.values_at("match_field", "match_operator", "match_value")).to all(be_nil)
    payments = create(:goal, business: book, account: create(:account, business: book))
    expect(payments.account_id).to be_nil
  end

  it "does not let the kind change after creation" do
    goal = create(:goal, business: book)
    expect(goal.update(kind: "savings", account: create(:account, business: book))).to be(false)
    expect(goal.errors[:kind]).to be_present
  end

  it "positions new goals last and orders by position" do
    first = create(:goal, business: book)
    second = create(:goal, business: book)
    expect(book.goals.ordered).to eq([ first, second ])
    expect(second.position).to eq(first.position + 1)
  end

  it "exposes its matcher as a rule RuleEngine understands" do
    goal = build(:goal, business: book, match_value: "Tony", match_amount_max: "2,000")
    expect(goal).to be_matcher
    expect(RuleEngine.matches?(goal.matcher_rule, { payee: "ZELLE TONY RUSSO", memo: nil, amount_cents: -1_500_00 })).to be(true)
    expect(RuleEngine.matches?(goal.matcher_rule, { payee: "ZELLE TONY RUSSO", memo: nil, amount_cents: -2_500_00 })).to be(false)
    expect(goal.matcher_description).to eq("payee contains \"Tony\" · ≤ $2,000.00")
    expect(build(:goal, business: book, match_field: nil, match_operator: nil, match_value: nil)).not_to be_matcher
  end

  describe "matching on save" do
    let(:account) { create(:account, business: book) }

    it "backfills existing transactions when created and reports the count" do
      create(:transaction, account: account, payee: "ZELLE TONY", amount_cents: -500_00)
      goal = create(:goal, business: book)
      expect(goal.rematched_count).to eq(1)
      expect(goal.transactions.count).to eq(1)
    end

    it "relinks when the matcher changes but not on a rename" do
      tony = create(:transaction, account: account, payee: "ZELLE TONY", amount_cents: -500_00)
      ann = create(:transaction, account: account, payee: "ZELLE ANN", amount_cents: -500_00)
      goal = create(:goal, business: book)
      goal.update!(name: "Renamed")
      expect(goal.rematched_count).to be_nil
      goal.update!(match_value: "ann")
      expect([ tony, ann ].map { _1.reload.goal_id }).to eq([ nil, goal.id ])
    end

    it "keeps links when archived and relinks once when unarchived" do
      row = create(:transaction, account: account, payee: "TONY", amount_cents: -500_00)
      goal = create(:goal, business: book)
      goal.update!(archived_at: Time.current)
      later = create(:transaction, account: account, payee: "TONY AGAIN", amount_cents: -700_00)
      expect(row.reload.goal).to eq(goal)
      expect(later.reload.goal).to be_nil
      goal.update!(archived_at: nil)
      expect(row.reload.goal).to eq(goal)
      expect(later.reload.goal).to eq(goal)
      expect(Transaction.where(goal: goal).count).to eq(2)
    end

    it "reports only its own matcher links as rematched_count" do
      create(:transaction, account: account, payee: "TONY ONE", amount_cents: -500_00)
      create(:transaction, account: account, payee: "TONY TWO", amount_cents: -500_00)
      a = create(:goal, business: book)
      expect(a.rematched_count).to eq(2)
      b = create(:goal, business: book, match_value: "nomatch")
      expect(b.rematched_count).to eq(0)
      expect(a.transactions.count).to eq(2)
    end

    it "moves a deleted goal's matcher rows to another active goal" do
      first = create(:goal, business: book, match_value: "tony")
      second = create(:goal, business: book, match_value: "tony")
      row = create(:transaction, account: account, payee: "TONY", amount_cents: -500_00)
      GoalMatcher.new(book).rematch
      expect(row.reload.goal).to eq(first)
      first.destroy!
      expect(row.reload.attributes.values_at("goal_id", "goal_linked_by")).to eq([ second.id, "matcher" ])
    end

    it "gives matcher links to the new top goal after a reorder, leaving hand links alone" do
      first = create(:goal, business: book, match_value: "tony")
      second = create(:goal, business: book, match_value: "tony")
      auto = create(:transaction, account: account, payee: "TONY", amount_cents: -500_00)
      GoalMatcher.new(book).rematch
      hand = create(:transaction, account: account, payee: "TONY", amount_cents: -500_00, goal: first, goal_linked_by: "user")
      expect(auto.reload.goal).to eq(first)
      second.move_to!(1)
      expect(book.goals.ordered).to eq([ second, first ])
      expect([ auto, hand ].map { _1.reload.goal }).to eq([ second, first ])
    end

    it "frees matcher links and turns hand links into hand unlinks when deleted" do
      goal = create(:goal, business: book)
      auto = create(:transaction, account: account, payee: "TONY", amount_cents: -500_00)
      GoalMatcher.new(book).rematch
      hand = create(:transaction, account: account, payee: "X", amount_cents: -500_00, goal: goal, goal_linked_by: "user")
      goal.destroy!
      expect(auto.reload.attributes.values_at("goal_id", "goal_linked_by")).to eq([ nil, nil ])
      expect(hand.reload.attributes.values_at("goal_id", "goal_linked_by")).to eq([ nil, "user" ])
    end
  end
end
