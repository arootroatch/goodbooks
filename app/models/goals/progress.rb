module Goals
  # How far each goal has come. Payment goals: the linked, non-excluded outflows net of refunds. Savings goals: their
  # account's balance poured into the active savings goals on that account, highest priority first.
  class Progress
    Row = Data.define(:goal, :saved_cents, :balance_unknown) do
      def target_cents = goal.target_cents
      def balance_unknown? = balance_unknown
      def met? = !balance_unknown && saved_cents >= target_cents
      def percent = [ saved_cents * 100 / target_cents, 100 ].min
    end

    def self.for_book(book) = for_goals(book.goals.active.ordered.includes(:account))

    def self.for_goals(goals)
      goals = goals.to_a
      paid = Transaction.where(goal_id: goals.select(&:payments?).map(&:id), excluded: false).group(:goal_id).sum(:amount_cents)
      allocated = allocate(goals.select { _1.savings? && !_1.archived? })
      goals.map do |goal|
        if goal.payments?
          Row.new(goal:, saved_cents: [ -paid.fetch(goal.id, 0), 0 ].max, balance_unknown: false)
        else
          allocated.fetch(goal.id) { Row.new(goal:, saved_cents: 0, balance_unknown: false) }
        end
      end
    end

    def self.allocate(savings_goals)
      savings_goals.sort_by { [ _1.position, _1.id ] }.group_by(&:account).each_with_object({}) do |(account, goals), rows|
        balance = account.balance_cents
        remaining = [ balance.to_i, 0 ].max
        goals.each do |goal|
          share = balance.nil? ? 0 : [ goal.target_cents, remaining ].min
          remaining -= share
          rows[goal.id] = Row.new(goal:, saved_cents: share, balance_unknown: balance.nil?)
        end
      end
    end
    private_class_method :allocate
  end
end
