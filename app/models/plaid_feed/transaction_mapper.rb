module PlaidFeed
  # A Plaid transaction hash (from PlaidGateway or FakePlaidGateway) → transaction attributes. Pending → nil.
  module TransactionMapper
    class InvalidAmount < StandardError; end

    Row = Data.define(:plaid_transaction_id, :plaid_account_id, :posted_on, :amount_cents, :payee, :memo) do
      def attributes = { plaid_transaction_id:, posted_on:, amount_cents:, payee:, memo: }
    end

    def self.call(plaid)
      return nil if plaid[:pending]

      merchant = plaid[:merchant_name].to_s.squish.presence
      name = plaid[:name].to_s.squish.presence
      Row.new(
        plaid_transaction_id: plaid[:transaction_id],
        plaid_account_id: plaid[:account_id],
        posted_on: to_date(plaid[:date]),
        amount_cents: -cents(plaid[:amount]),
        payee: merchant || name || "Unknown",
        memo: (name if merchant && name && name != merchant)
      )
    end

    def self.cents(amount)
      cents = BigDecimal(amount.to_s) * 100
      raise InvalidAmount, "Plaid amount #{amount} is not a whole number of cents" unless cents.frac.zero?

      cents.to_i
    end

    def self.to_date(value) = value.is_a?(Date) ? value : Date.iso8601(value.to_s)

    private_class_method :cents, :to_date
  end
end
