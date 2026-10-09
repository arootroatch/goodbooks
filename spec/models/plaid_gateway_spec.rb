require "rails_helper"

RSpec.describe PlaidGateway do
  subject(:gateway) { described_class.new(client_id: "client", secret: "secret", environment: "sandbox") }

  let(:base) { "https://sandbox.plaid.com" }
  let(:user) { create(:user) }

  def stub_plaid(path, body, status: 200)
    stub_request(:post, "#{base}#{path}").to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def plaid_error(code, type: "ITEM_ERROR")
    { error_type: type, error_code: code, error_message: "the message", display_message: nil, request_id: "r" }
  end

  it "rejects an unknown environment" do
    expect { described_class.new(client_id: "c", secret: "s", environment: "development") }.to raise_error(ArgumentError, /sandbox or production/)
  end

  it "creates a link token for transactions, or an update-mode token for an access token" do
    allow(described_class).to receive(:webhook_url).and_return("https://books.example.com/plaid/webhooks")
    stub_plaid("/link/token/create", { link_token: "link-sandbox-1", expiration: "2026-10-09T00:00:00Z", request_id: "r" })
    expect(gateway.create_link_token(user: user)).to eq("link-sandbox-1")
    expect(WebMock).to have_requested(:post, "#{base}/link/token/create").with { |req|
      body = JSON.parse(req.body)
      body["products"] == [ "transactions" ] && body["user"] == { "client_user_id" => user.id.to_s } &&
        body["webhook"] == "https://books.example.com/plaid/webhooks" && req.headers["Plaid-Client-Id"] == "client"
    }
    gateway.create_link_token(user: user, access_token: "access-1")
    expect(WebMock).to have_requested(:post, "#{base}/link/token/create").with { |req|
      body = JSON.parse(req.body)
      body["access_token"] == "access-1" && !body.key?("products")
    }
  end

  it "exchanges a public token and reads the institution name" do
    stub_plaid("/item/public_token/exchange", { access_token: "access-1", item_id: "item-1", request_id: "r" })
    stub_plaid("/item/get", { item: { item_id: "item-1", institution_id: "ins_1", institution_name: "First Platypus Bank" }, request_id: "r" })
    expect(gateway.exchange_public_token("public-1")).to eq(access_token: "access-1", item_id: "item-1")
    expect(gateway.institution_name("access-1")).to eq("First Platypus Bank")
  end

  it "lists accounts as plain hashes" do
    stub_plaid("/accounts/get", { accounts: [ { account_id: "a1", name: "Plaid Checking", mask: "0000", type: "depository",
                                                subtype: "checking", balances: {} } ], item: { item_id: "item-1" }, request_id: "r" })
    expect(gateway.accounts("access-1")).to eq([ { account_id: "a1", name: "Plaid Checking", mask: "0000", type: "depository", subtype: "checking" } ])
  end

  it "returns a sync page as plain hashes and sends the cursor and page size" do
    stub_plaid("/transactions/sync", {
      added: [ { transaction_id: "t1", account_id: "a1", amount: 12.34, date: "2026-10-01", name: "SQ *JOES", merchant_name: "Joes",
                 pending: false } ],
      modified: [], removed: [ { transaction_id: "t0", account_id: "a1" } ], next_cursor: "c2", has_more: true, request_id: "r"
    })
    page = gateway.transactions_sync("access-1", "c1")
    expect(page[:added]).to eq([ { transaction_id: "t1", account_id: "a1", amount: 12.34, date: Date.new(2026, 10, 1), name: "SQ *JOES",
                                   merchant_name: "Joes", pending: false } ])
    expect(page[:removed]).to eq([ { transaction_id: "t0", account_id: "a1" } ])
    expect(page.slice(:modified, :next_cursor, :has_more)).to eq(modified: [], next_cursor: "c2", has_more: true)
    expect(WebMock).to have_requested(:post, "#{base}/transactions/sync").with { |req|
      JSON.parse(req.body).slice("access_token", "cursor", "count") == { "access_token" => "access-1", "cursor" => "c1", "count" => 500 }
    }
  end

  it "omits a blank cursor on the first sync" do
    stub_plaid("/transactions/sync", { added: [], modified: [], removed: [], next_cursor: "c1", has_more: false, request_id: "r" })
    gateway.transactions_sync("access-1", nil)
    expect(WebMock).to have_requested(:post, "#{base}/transactions/sync").with { |req| !JSON.parse(req.body).key?("cursor") }
  end

  it "removes an item and fetches a webhook verification key" do
    stub_plaid("/item/remove", { request_id: "r" })
    stub_plaid("/webhook_verification_key/get", { key: { alg: "ES256", crv: "P-256", kid: "k1", kty: "EC", use: "sig", x: "x", y: "y",
                                                         created_at: 1, expired_at: nil }, request_id: "r" })
    expect(gateway.item_remove("access-1")).to be_nil
    expect(gateway.webhook_verification_key("k1")).to include("kid" => "k1", "kty" => "EC", "alg" => "ES256", "expired_at" => nil)
  end

  it "translates Plaid errors" do
    stub_plaid("/transactions/sync", plaid_error("ITEM_LOGIN_REQUIRED"), status: 400)
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::LoginRequired, "ITEM_LOGIN_REQUIRED: the message")

    stub_plaid("/transactions/sync", plaid_error("TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION", type: "TRANSACTIONS_ERROR"), status: 400)
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::MutationDuringPagination)

    stub_plaid("/transactions/sync", plaid_error("RATE_LIMIT", type: "RATE_LIMIT_EXCEEDED"), status: 429)
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::TransientError)

    stub_plaid("/transactions/sync", plaid_error("INTERNAL_SERVER_ERROR", type: "API_ERROR"), status: 500)
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::TransientError)

    stub_plaid("/transactions/sync", plaid_error("INVALID_ACCESS_TOKEN", type: "INVALID_INPUT"), status: 400)
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::Error) { |e|
      expect(e).not_to be_a(described_class::TransientError)
      expect(e.code).to eq("INVALID_ACCESS_TOKEN")
    }

    stub_request(:post, "#{base}/transactions/sync").to_timeout
    expect { gateway.transactions_sync("a", nil) }.to raise_error(described_class::TransientError)
  end

  describe ".from_env" do
    let(:keys) { { "PLAID_CLIENT_ID" => "c", "PLAID_SECRET" => "s", "PLAID_ENV" => "sandbox" } }

    it "builds a real gateway when all three keys are set" do
      expect(described_class.from_env(keys, rails_env: "production".inquiry)).to be_a(described_class)
    end

    it "is disabled in production without keys" do
      expect(described_class.from_env(keys.except("PLAID_SECRET"), rails_env: "production".inquiry)).to be_nil
    end

    it "builds the webhook URL from APP_HOST" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("APP_HOST").and_return("books.example.com")
      expect(described_class.webhook_url).to eq("https://books.example.com/plaid/webhooks")
      allow(ENV).to receive(:[]).with("APP_HOST").and_return(nil)
      expect(described_class.webhook_url).to be_nil
    end
  end
end
