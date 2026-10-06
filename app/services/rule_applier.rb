class RuleApplier
  def initialize(business)
    @rules = business.rules.ordered.includes(:category).to_a
  end

  def apply(transactions)
    transactions.count do |txn|
      next false unless txn.inbox? && !txn.categorized_by_user?

      rule = RuleEngine.match(txn.rule_attributes, @rules)
      next false unless rule

      txn.update!(
        rule: rule,
        categorized_by: "rule",
        transfer: rule.outcome == "transfer",
        category: rule.outcome == "categorize" ? rule.category : nil
      )
      true
    end
  end
end
