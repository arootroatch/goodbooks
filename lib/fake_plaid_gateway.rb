# Stands in for PlaidGateway in tests, in development without Plaid keys, and in demo:seed. No network.
class FakePlaidGateway
  KID = "fake-plaid-key"
  DEFAULT_ACCOUNTS = [
    { account_id: "fake-checking", name: "Plaid Checking", mask: "0000", type: "depository", subtype: "checking" },
    { account_id: "fake-savings", name: "Plaid Saving", mask: "1111", type: "depository", subtype: "savings" },
    { account_id: "fake-card", name: "Plaid Credit Card", mask: "3333", type: "credit", subtype: "credit card" }
  ].freeze
  DEMO_PUBLIC_TOKEN = "public-demo"
  DEMO_ACCOUNTS = [
    { account_id: "demo-operating", name: "Business Operating", mask: "4821", type: "depository", subtype: "checking" },
    { account_id: "demo-card", name: "Business Visa", mask: "9034", type: "credit", subtype: "credit card" },
    { account_id: "demo-joint", name: "Joint Checking", mask: "1177", type: "depository", subtype: "checking" }
  ].freeze
  EMPTY_PAGE = { added: [], modified: [], removed: [] }.freeze

  attr_reader :calls

  # A Plaid-shaped transaction hash. Plaid's sign: positive amount = money out of the account.
  def self.plaid_txn(id, account_id:, amount:, date:, name:, merchant_name: nil, pending: false)
    { transaction_id: id, account_id: account_id, amount: amount, date: date, name: name, merchant_name: merchant_name, pending: pending }
  end

  def self.access_token_for(public_token) = "access-fake-#{Digest::SHA256.hexdigest(public_token.to_s)[0, 12]}"

  def initialize(accounts: DEFAULT_ACCOUNTS)
    @accounts = accounts
    @pages = Hash.new { |hash, token| hash[token] = [] }
    @failures = Hash.new { |hash, name| hash[name] = [] }
    @calls = []
    @key = OpenSSL::PKey::EC.generate("prime256v1")
    @key_expired_at = nil
  end

  def fake? = true

  def add_page(access_token, added: [], modified: [], removed: [])
    @pages[access_token] << { added: added, modified: modified, removed: removed }
  end

  def fail_next(method_name, error)
    @failures[method_name] << error
  end

  def expire_key!
    @key_expired_at = Time.current.to_i
  end

  def sign_webhook(body, iat: Time.current.to_i, key: nil)
    JWT.encode({ iat: iat, request_body_sha256: Digest::SHA256.hexdigest(body) }, key || @key, "ES256", { kid: KID })
  end

  def create_link_token(user:, access_token: nil)
    record(:create_link_token) { "link-fake-#{user.id}#{"-update" if access_token}" }
  end

  def exchange_public_token(public_token)
    record(:exchange_public_token) do
      access_token = self.class.access_token_for(public_token)
      { access_token: access_token, item_id: access_token.sub("access-", "item-") }
    end
  end

  def institution_name(_access_token) = record(:institution_name) { "Demo Bank" }

  def accounts(access_token)
    record(:accounts) { (access_token == self.class.access_token_for(DEMO_PUBLIC_TOKEN) ? DEMO_ACCOUNTS : @accounts).map(&:dup) }
  end

  def transactions_sync(access_token, cursor)
    record(:transactions_sync) do
      pages = @pages[access_token]
      index = cursor.to_s.delete_prefix("page-").to_i
      if index < pages.size
        pages[index].merge(next_cursor: "page-#{index + 1}", has_more: index + 1 < pages.size)
      else
        EMPTY_PAGE.merge(next_cursor: cursor.presence || "page-0", has_more: false)
      end
    end
  end

  def item_remove(_access_token) = record(:item_remove) { nil }

  def webhook_verification_key(kid)
    record(:webhook_verification_key) do
      raise PlaidGateway::Error.new("INVALID_WEBHOOK_VERIFICATION_KEY_ID: unknown key", code: "INVALID_WEBHOOK_VERIFICATION_KEY_ID") unless kid == KID

      JWT::JWK.new(@key, kid: KID).export.transform_keys(&:to_s)
        .merge("alg" => "ES256", "use" => "sig", "created_at" => 1, "expired_at" => @key_expired_at)
    end
  end

  private

  def record(method_name)
    @calls << method_name
    failure = @failures[method_name].shift
    raise failure if failure

    yield
  end
end
