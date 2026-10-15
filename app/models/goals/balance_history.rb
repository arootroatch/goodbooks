module Goals
  # An account's non-excluded transactions, newest first, each with the balance after it. Manual and CSV accounts run
  # forward from the opening balance; Plaid accounts run backward from the reported balance over the last 12 months.
  class BalanceHistory
    Entry = Data.define(:txn, :balance_cents)

    def self.for(account, today: Date.current)
      return [] unless account.balance_known?

      rows = account.transactions.where(excluded: false)
      if account.plaid?
        balance = account.reported_balance_cents
        rows.where(posted_on: (today << 12)..).order(posted_on: :desc, id: :desc).map do |txn|
          Entry.new(txn:, balance_cents: balance).tap { balance -= txn.amount_cents }
        end
      else
        balance = account.opening_balance_cents
        rows.where("posted_on > ?", account.opening_balance_on).order(:posted_on, :id)
          .map { |txn| Entry.new(txn:, balance_cents: balance += txn.amount_cents) }.reverse
      end
    end
  end
end
