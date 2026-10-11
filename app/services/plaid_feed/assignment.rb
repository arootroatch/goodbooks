module PlaidFeed
  # Applies the assignment page: each Plaid account is skipped, becomes a new account in a book the user owns,
  # or feeds an existing manual/CSV account there. All rows apply together or not at all.
  class Assignment
    Result = Data.define(:errors) do
      def ok? = errors.empty?
    end

    def self.call(item:, user:, plaid_accounts:, rows:) = new(item, user).call(plaid_accounts, rows)

    # The one definition of "an existing account a Plaid account may feed", shared by the page and the service.
    def self.attachable(books) = Account.where(business: books).active.where(plaid_account_id: nil, source: %w[manual csv])

    def self.kind_for(type, subtype)
      return "credit" if type == "credit"
      return "other" unless type == "depository"

      %w[checking savings].include?(subtype) ? subtype : "other"
    end

    def initialize(item, user)
      @item = item
      @books = user.owned_books
    end

    def call(plaid_accounts, rows)
      by_id = plaid_accounts.index_by { _1[:account_id] }
      assigned = @item.accounts.pluck(:plaid_account_id).to_set
      @errors = {}
      seen = Set.new
      ApplicationRecord.transaction do
        rows.each do |row|
          key = row[:plaid_account].to_s
          plaid = by_id[key]
          next @errors[key] = "That account isn't part of this connection" unless plaid
          next @errors[key] = "This bank account appears twice." unless seen.add?(key)
          next if assigned.include?(key)

          apply(plaid, row)
        end
        raise ActiveRecord::Rollback if @errors.any?
      end
      Result.new(errors: @errors)
    end

    private

    def apply(plaid, row)
      case row[:choice].to_s
      when "", "skip" then nil
      when "new" then create_account(plaid, row)
      when "attach" then attach_account(plaid, row)
      else @errors[plaid[:account_id]] = "Choose skip, new account, or existing account"
      end
    end

    def create_account(plaid, row)
      book = @books.find_by(id: row[:book])
      return @errors[plaid[:account_id]] = "Choose a book you own" unless book

      sync_from = parse_date(plaid, row[:sync_from])
      return if @errors.key?(plaid[:account_id])

      account = book.accounts.new(name: row[:name].presence || plaid[:name], source: "plaid",
                                  kind: self.class.kind_for(plaid[:type], plaid[:subtype]), plaid_sync_from: sync_from, **link(plaid))
      @errors[plaid[:account_id]] = account.errors.full_messages.to_sentence unless account.save
    end

    def attach_account(plaid, row)
      account = self.class.attachable(@books).find_by(id: row[:target])
      return @errors[plaid[:account_id]] = "Choose an existing manual or CSV account in a book you own" unless account

      sync_from = row[:sync_from].present? ? parse_date(plaid, row[:sync_from]) : account.transactions.maximum(:posted_on)
      return if @errors.key?(plaid[:account_id])

      @errors[plaid[:account_id]] = account.errors.full_messages.to_sentence unless
        account.update(source: "plaid", plaid_sync_from: sync_from, **link(plaid))
    end

    def link(plaid) = { plaid_item: @item, plaid_account_id: plaid[:account_id], plaid_mask: plaid[:mask], plaid_name: plaid[:name] }

    def parse_date(plaid, value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      @errors[plaid[:account_id]] = "Sync from is not a valid date"
      nil
    end
  end
end
