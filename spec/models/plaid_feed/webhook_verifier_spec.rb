require "rails_helper"

RSpec.describe PlaidFeed::WebhookVerifier do
  let(:key) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:jwk) { JWT::JWK.new(key, kid: "k1").export.transform_keys(&:to_s).merge("alg" => "ES256", "expired_at" => nil) }
  let(:now) { Time.zone.parse("2026-10-08 12:00:00") }
  let(:body) { %({"webhook_type":"TRANSACTIONS","webhook_code":"SYNC_UPDATES_AVAILABLE","item_id":"item-1"}) }
  let(:verifier) { described_class.new(key_fetcher: ->(kid) { kid == "k1" ? jwk : nil }, now: now) }

  def token(signed_body: body, iat: now.to_i, signing_key: key, headers: { kid: "k1" })
    JWT.encode({ iat: iat, request_body_sha256: Digest::SHA256.hexdigest(signed_body) }, signing_key, "ES256", headers)
  end

  def invalid(token_value, message = nil)
    expect { verifier.verify!(body: body, token: token_value) }.to raise_error(described_class::Invalid, message)
  end

  it "accepts a fresh token from a current Plaid key whose hash matches the body" do
    expect(verifier.verify!(body: body, token: token)).to be(true)
    expect(verifier.verify!(body: body, token: token(iat: (now - 4.minutes).to_i))).to be(true)
  end

  it "rejects a missing or malformed token" do
    invalid(nil, /missing/)
    invalid("")
    invalid("not-a-jwt")
  end

  it "rejects any algorithm but ES256" do
    invalid(JWT.encode({ iat: now.to_i }, "secret", "HS256", { kid: "k1" }), /algorithm/)
    unsigned = [ { alg: "none", kid: "k1" }, { iat: now.to_i, request_body_sha256: Digest::SHA256.hexdigest(body) } ]
      .map { Base64.urlsafe_encode64(_1.to_json, padding: false) }.join(".") + "."
    invalid(unsigned, /algorithm/)
  end

  it "rejects a missing, unknown, or expired key" do
    invalid(token(headers: {}), /key id/)
    invalid(token(headers: { kid: "other" }), /unknown key/)
    jwk["expired_at"] = now.to_i - 60
    invalid(token, /expired key/)
  end

  it "rejects a signature from another key" do
    invalid(token(signing_key: OpenSSL::PKey::EC.generate("prime256v1")))
  end

  it "rejects a token issued more than five minutes ago, or without iat" do
    invalid(token(iat: (now - 6.minutes).to_i), /too old/)
    invalid(JWT.encode({ request_body_sha256: Digest::SHA256.hexdigest(body) }, key, "ES256", { kid: "k1" }))
  end

  it "rejects a body that was changed after signing" do
    invalid(token(signed_body: body.sub("item-1", "item-2")), /body hash/)
  end

  it "turns a key fetch failure into Invalid" do
    failing = described_class.new(key_fetcher: ->(_) { raise PlaidGateway::Error, "boom" }, now: now)
    expect { failing.verify!(body: body, token: token) }.to raise_error(described_class::Invalid, /boom/)
  end
end
