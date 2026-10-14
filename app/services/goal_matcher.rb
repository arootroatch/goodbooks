# Links transactions to a book's payment goals. A row is eligible when it's an outflow, not excluded, and has no goal
# link of any kind (a hand unlink leaves goal_linked_by "user", which keeps the matcher away). The first active goal
# by position whose matcher hits wins. Only goal columns are written, so categorization is never touched.
class GoalMatcher
  def initialize(book)
    @book = book
    @goals = book.goals.active.payments.ordered.to_a.select(&:matcher?)
  end

  def apply(transactions)
    return 0 if @goals.empty?

    transactions.count do |txn|
      next false unless eligible?(txn)

      goal = @goals.find { RuleEngine.matches?(_1.matcher_rule, txn.rule_attributes) }
      next false unless goal

      txn.update_columns(goal_id: goal.id, goal_linked_by: "matcher", updated_at: Time.current)
      true
    end
  end

  # Clears every active payment goal's matcher links in the book, then matches again. Archived goals keep their links.
  def rematch
    Transaction.where(goal_id: @book.goals.active.payments.select(:id), goal_linked_by: "matcher")
      .update_all(goal_id: nil, goal_linked_by: nil, updated_at: Time.current)
    apply(Transaction.for_businesses(@book.id).where(goal_id: nil, goal_linked_by: nil, excluded: false)
      .where("transactions.amount_cents < 0").order(:posted_on, :id).to_a)
  end

  private

  def eligible?(txn) = txn.goal_id.nil? && txn.goal_linked_by.nil? && !txn.excluded? && txn.amount_cents.to_i.negative?
end
