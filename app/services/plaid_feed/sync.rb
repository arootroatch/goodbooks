module PlaidFeed
  # Applies one item's Plaid changes to the books in a single DB transaction, then saves the new cursor.
  # Plaid rows claim matching CSV or hand-entered rows instead of duplicating them; bank changes that the
  # app's rules reject, or that would undo the user's work, flag the row for review instead.
  class Sync
    MAX_RESTARTS = 3

    Result = Data.define(:inserted, :claimed, :modified, :flagged, :excluded)

    def self.call(item, gateway: PlaidGateway.current) = new(item, gateway).call

    def initialize(item, gateway)
      @item = item
      @gateway = gateway
      @counts = Hash.new(0)
    end

    def call
      added, modified, removed, cursor = fetch
      ApplicationRecord.transaction do
        accounts = @item.accounts.includes(:business).where.not(plaid_account_id: nil).index_by(&:plaid_account_id)
        inserted = apply_added(added, accounts)
        modified.each { apply_modified(_1, accounts) }
        removed.each { apply_removed(_1, accounts) }
        fresh = Transaction.where(id: inserted.map(&:id)).includes(account: :business)
        fresh.group_by { _1.account.business }.each { |book, rows| RuleApplier.new(book).apply(rows) }
        @item.update!(cursor: cursor, last_synced_at: Time.current, status: "ok", last_error: nil)
      end
      Result.new(**Result.members.index_with { @counts[_1] })
    end

    private

    def fetch
      restarts = 0
      begin
        added, modified, removed = [], [], []
        cursor = @item.cursor
        loop do
          page = @gateway.transactions_sync(@item.access_token, cursor)
          added.concat(page[:added])
          modified.concat(page[:modified])
          removed.concat(page[:removed])
          cursor = page[:next_cursor]
          break unless page[:has_more]
        end
        [ added, modified, removed, cursor ]
      rescue PlaidGateway::MutationDuringPagination
        restarts += 1
        raise PlaidGateway::TransientError, "Plaid's data changed during the sync; it will be retried" if restarts > MAX_RESTARTS

        retry
      end
    end

    def apply_added(added, accounts)
      added.group_by { _1[:account_id] }.flat_map do |plaid_account_id, plaid_rows|
        account = accounts[plaid_account_id]
        next [] unless account

        rows = plaid_rows.filter_map { TransactionMapper.call(_1) }
        rows.reject! { |row| account.plaid_sync_from && row.posted_on < account.plaid_sync_from }
        known = account.transactions.where(plaid_transaction_id: rows.map(&:plaid_transaction_id)).index_by(&:plaid_transaction_id)
        fresh, repeated = rows.partition { known[_1.plaid_transaction_id].nil? }
        repeated.each { update_from_bank(known[_1.plaid_transaction_id], _1) }
        insert_or_claim(account, fresh)
      end
    end

    def insert_or_claim(account, rows)
      claims = ClaimMatcher.pair_records(rows, account.transactions.where(plaid_transaction_id: nil), key: :plaid_transaction_id)
      rows.filter_map do |row|
        if (existing = claims[row.plaid_transaction_id])
          existing.update!(plaid_transaction_id: row.plaid_transaction_id)
          @counts[:claimed] += 1
          nil
        else
          @counts[:inserted] += 1
          account.transactions.create!(row.attributes)
        end
      end
    end

    def apply_modified(plaid, accounts)
      account = accounts[plaid[:account_id]]
      row = account && TransactionMapper.call(plaid)
      txn = row && account.transactions.find_by(plaid_transaction_id: row.plaid_transaction_id)
      update_from_bank(txn, row) if txn
    end

    def update_from_bank(txn, row)
      return if txn.excluded?

      txn.assign_attributes(posted_on: row.posted_on, amount_cents: row.amount_cents)
      return unless txn.changed?

      if txn.save
        @counts[:modified] += 1
      else
        txn.restore_attributes
        txn.update!(review_reason: "changed_by_bank")
        @counts[:flagged] += 1
      end
    end

    def apply_removed(plaid, accounts)
      txn = Transaction.where(account: accounts.values).find_by(plaid_transaction_id: plaid[:transaction_id])
      return if txn.nil? || txn.excluded?

      if txn.categorized_by_user? || txn.invoice_payments.exists?
        txn.update!(review_reason: "removed_by_bank")
        @counts[:flagged] += 1
      else
        txn.update!(excluded: true)
        @counts[:excluded] += 1
      end
    end
  end
end
