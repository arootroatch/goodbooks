# The only code that talks to Plaid. Returns plain hashes so FakePlaidGateway can stand in for it.
class PlaidGateway
  class Error < StandardError
    attr_reader :code

    def initialize(message = nil, code: nil)
      super(message)
      @code = code
    end
  end

  class LoginRequired < Error; end
  class TransientError < Error; end
  class MutationDuringPagination < Error; end

  ENVIRONMENTS = %w[sandbox production].freeze
  TRANSIENT_TYPES = %w[RATE_LIMIT_EXCEEDED API_ERROR INSTITUTION_ERROR].freeze
  SYNC_PAGE_SIZE = 500
  TIMEOUT_SECONDS = 30

  class << self
    def current
      @current = from_env unless defined?(@current)
      @current
    end

    attr_writer :current

    def reset!
      remove_instance_variable(:@current) if defined?(@current)
    end

    def enabled? = !current.nil?

    def from_env(env = ENV, rails_env: Rails.env)
      client_id, secret, environment = env.values_at("PLAID_CLIENT_ID", "PLAID_SECRET", "PLAID_ENV")
      if [ client_id, secret, environment ].all?(&:present?)
        new(client_id: client_id, secret: secret, environment: environment)
      elsif !rails_env.production?
        FakePlaidGateway.new
      end
    end

    def webhook_url
      host = ENV["APP_HOST"].presence
      host && "https://#{host}/plaid/webhooks"
    end
  end

  def initialize(client_id:, secret:, environment:)
    raise ArgumentError, "PLAID_ENV must be sandbox or production" unless ENVIRONMENTS.include?(environment)

    require "plaid"
    configuration = Plaid::Configuration.new
    configuration.server_index = Plaid::Configuration::Environment.fetch(environment)
    configuration.api_key["PLAID-CLIENT-ID"] = client_id
    configuration.api_key["PLAID-SECRET"] = secret
    configuration.timeout = TIMEOUT_SECONDS
    @api = Plaid::PlaidApi.new(Plaid::ApiClient.new(configuration))
  end

  def fake? = false

  def create_link_token(user:, access_token: nil)
    request = { user: { client_user_id: user.id.to_s }, client_name: "goodbooks", country_codes: [ "US" ], language: "en" }
    request[:webhook] = self.class.webhook_url if self.class.webhook_url
    if access_token
      request[:access_token] = access_token
    else
      request[:products] = [ "transactions" ]
    end
    call { @api.link_token_create(Plaid::LinkTokenCreateRequest.new(request)).link_token }
  end

  def exchange_public_token(public_token)
    response = call { @api.item_public_token_exchange(Plaid::ItemPublicTokenExchangeRequest.new(public_token: public_token)) }
    { access_token: response.access_token, item_id: response.item_id }
  end

  def institution_name(access_token)
    item = call { @api.item_get(Plaid::ItemGetRequest.new(access_token: access_token)).item }
    item.institution_name.presence || "Your bank"
  end

  def accounts(access_token)
    call { @api.accounts_get(Plaid::AccountsGetRequest.new(access_token: access_token)).accounts }.map do |account|
      { account_id: account.account_id, name: account.name, mask: account.mask, type: account.type.to_s, subtype: account.subtype.to_s }
    end
  end

  def transactions_sync(access_token, cursor)
    request = { access_token: access_token, count: SYNC_PAGE_SIZE }
    request[:cursor] = cursor if cursor.present?
    response = call { @api.transactions_sync(Plaid::TransactionsSyncRequest.new(request)) }
    {
      added: response.added.map { transaction_hash(_1) },
      modified: response.modified.map { transaction_hash(_1) },
      removed: response.removed.map { { transaction_id: _1.transaction_id, account_id: _1.account_id } },
      next_cursor: response.next_cursor,
      has_more: response.has_more
    }
  end

  def item_remove(access_token)
    call { @api.item_remove(Plaid::ItemRemoveRequest.new(access_token: access_token)) }
    nil
  end

  def webhook_verification_key(kid)
    key = call { @api.webhook_verification_key_get(Plaid::WebhookVerificationKeyGetRequest.new(key_id: kid)).key }
    key.to_hash.transform_keys(&:to_s)
  end

  private

  def transaction_hash(txn)
    { transaction_id: txn.transaction_id, account_id: txn.account_id, amount: txn.amount, date: txn.date,
      name: txn.name, merchant_name: txn.merchant_name, pending: txn.pending }
  end

  def call
    yield
  rescue Plaid::ApiError => e
    raise translate(e)
  end

  def translate(error)
    body = parse(error.response_body)
    code = body["error_code"].presence
    detail = body["error_message"].presence || (error.response_body.nil? ? error.message : "Plaid request failed")
    message = "#{code || "HTTP #{error.code || "error"}"}: #{detail}"
    error_class(code, body["error_type"], error.code).new(message, code: code)
  end

  def error_class(code, type, status)
    if code == "ITEM_LOGIN_REQUIRED" then LoginRequired
    elsif code == "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION" then MutationDuringPagination
    elsif status.to_i.zero? || status.to_i == 429 || status.to_i >= 500 || TRANSIENT_TYPES.include?(type) || code == "PRODUCT_NOT_READY"
      TransientError
    else Error
    end
  end

  def parse(raw)
    parsed = JSON.parse(raw.to_s)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
end
