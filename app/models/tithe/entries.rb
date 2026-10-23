module Tithe
  # The only place that knows which transactions are tithable income or tithe payments (spec §4).
  # Income counts only in tithable accounts; tithe payments count from any account. Rows left out of the tithe
  # come back as excluded entries so the ledger can list them.
  module Entries
    TITHABLE_INCOME_SQL = "categories.id IS NULL OR (categories.kind = 'income' AND categories.tithable = ?)".freeze

    def self.for(book)
      return [] unless book.tithe_start_on

      scope = Transaction.countable.for_businesses(book.id).where(posted_on: book.tithe_start_on..).includes(:account)
      income = scope.where("transactions.amount_cents > 0").where(accounts: { tithable: true })
        .left_joins(:category).where(TITHABLE_INCOME_SQL, true)
      payments = scope.joins(:category).where(categories: { tithe: true })
      income.map { entry(_1, cents: _1.amount_cents, kind: :income) } + payments.map { entry(_1, cents: -_1.amount_cents, kind: :payment) }
    end

    def self.entry(txn, cents:, kind:)
      Ledger::Entry.new(posted_on: txn.posted_on, cents:, kind:, source: txn, excluded: txn.tithe_excluded?)
    end
    private_class_method :entry
  end
end
