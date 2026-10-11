require "rails_helper"

RSpec.describe FakePlaidGateway do
  subject(:fake) { described_class.new }

  it "is installed as the gateway in every example" do
    expect(PlaidGateway.current).to be_a(described_class)
    expect(PlaidGateway).to be_enabled
    expect(plaid_gateway).to be(PlaidGateway.current)
  end

  it "exchanges tokens deterministically and lists the default accounts" do
    first = fake.exchange_public_token("public-a")
    expect(first).to eq(fake.exchange_public_token("public-a"))
    expect(first[:access_token]).to start_with("access-fake-")
    expect(first[:item_id]).to start_with("item-fake-")
    expect(fake.institution_name(first[:access_token])).to eq("Demo Bank")
    expect(fake.accounts(first[:access_token]).map { _1[:account_id] }).to eq(%w[fake-checking fake-savings fake-card])
    expect(fake.create_link_token(user: build_stubbed(:user, id: 5))).to eq("link-fake-5")
    expect(fake.create_link_token(user: build_stubbed(:user, id: 5), access_token: "x")).to eq("link-fake-5-update")
  end

  it "lists the demo accounts for the demo connection in any instance" do
    token = fake.exchange_public_token(described_class::DEMO_PUBLIC_TOKEN)[:access_token]
    expect(token).to eq(described_class.access_token_for(described_class::DEMO_PUBLIC_TOKEN))
    expect(described_class.new.accounts(token).map { _1[:account_id] }).to eq(%w[demo-operating demo-card demo-joint])
  end

  it "serves scripted pages by cursor, then empty pages" do
    txn = described_class.plaid_txn("t1", account_id: "fake-checking", amount: 5.0, date: Date.new(2026, 10, 1), name: "COFFEE")
    fake.add_page("access", added: [ txn ])
    fake.add_page("access", removed: [ { transaction_id: "t0", account_id: "fake-checking" } ])
    first = fake.transactions_sync("access", nil)
    expect(first).to eq(added: [ txn ], modified: [], removed: [], next_cursor: "page-1", has_more: true)
    second = fake.transactions_sync("access", "page-1")
    expect(second.slice(:next_cursor, :has_more)).to eq(next_cursor: "page-2", has_more: false)
    expect(fake.transactions_sync("access", "page-2")).to eq(added: [], modified: [], removed: [], next_cursor: "page-2", has_more: false)
    expect(fake.transactions_sync("other", nil)).to eq(added: [], modified: [], removed: [], next_cursor: "page-0", has_more: false)
  end

  it "raises scripted failures once, in order" do
    fake.fail_next(:transactions_sync, PlaidGateway::LoginRequired.new("ITEM_LOGIN_REQUIRED: login"))
    expect { fake.transactions_sync("access", nil) }.to raise_error(PlaidGateway::LoginRequired)
    expect { fake.transactions_sync("access", nil) }.not_to raise_error
    expect(fake.calls).to eq(%i[transactions_sync transactions_sync])
  end

  it "signs webhooks with a key it serves, and can expire that key" do
    token = fake.sign_webhook("{}")
    header = JWT.decode(token, nil, false).last
    expect(header).to include("alg" => "ES256", "kid" => described_class::KID)
    jwk = fake.webhook_verification_key(described_class::KID)
    payload, = JWT.decode(token, JWT::JWK.import(jwk.slice("kty", "crv", "x", "y").transform_keys(&:to_sym)).verify_key, true, algorithms: [ "ES256" ])
    expect(payload["request_body_sha256"]).to eq(Digest::SHA256.hexdigest("{}"))
    expect(jwk["expired_at"]).to be_nil
    fake.expire_key!
    expect(fake.webhook_verification_key(described_class::KID)["expired_at"]).to be_a(Integer)
    expect { fake.webhook_verification_key("other") }.to raise_error(PlaidGateway::Error)
  end
end
