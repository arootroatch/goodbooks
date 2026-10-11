module Tithe
  # The only place that knows which transactions are tithable income or tithe payments (spec §4).
  module Entries
    TITHABLE_INCOME_SQL = "categories.id IS NULL OR (categories.kind = 'income' AND categories.tithable = ?)".freeze

    def self.for(book)
      return [] unless book.tithe_start_on

      scope = Transaction.countable.for_businesses(book.id).where(posted_on: book.tithe_start_on..)
      income = scope.where("transactions.amount_cents > 0").left_joins(:category).where(TITHABLE_INCOME_SQL, true)
      payments = scope.joins(:category).where(categories: { tithe: true })
      income.map { Ledger::Entry.new(posted_on: _1.posted_on, cents: _1.amount_cents, kind: :income, source: _1) } +
        payments.map { Ledger::Entry.new(posted_on: _1.posted_on, cents: -_1.amount_cents, kind: :payment, source: _1) }
    end
  end
end
