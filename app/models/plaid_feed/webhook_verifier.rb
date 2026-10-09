module PlaidFeed
  # A Plaid webhook is genuine when its Plaid-Verification header is an ES256 JWT signed by a current Plaid key,
  # issued within MAX_AGE, whose request_body_sha256 claim matches the raw body.
  class WebhookVerifier
    MAX_AGE = 5.minutes

    class Invalid < StandardError; end

    def initialize(key_fetcher:, now: Time.current)
      @key_fetcher = key_fetcher
      @now = now
    end

    def verify!(body:, token:)
      raise Invalid, "missing Plaid-Verification header" if token.blank?

      header = JWT.decode(token, nil, false).last
      raise Invalid, "unexpected algorithm #{header["alg"].inspect}" unless header["alg"] == "ES256"
      raise Invalid, "missing key id" if header["kid"].blank?

      payload, = JWT.decode(token, verify_key(header["kid"]), true, algorithms: [ "ES256" ])
      raise Invalid, "token is too old" if Integer(payload["iat"]) < (@now - MAX_AGE).to_i

      digest = Digest::SHA256.hexdigest(body.to_s)
      raise Invalid, "body hash mismatch" unless ActiveSupport::SecurityUtils.secure_compare(digest, payload["request_body_sha256"].to_s)

      true
    rescue JWT::DecodeError, PlaidGateway::Error, ArgumentError, TypeError => e
      raise Invalid, e.message
    end

    private

    def verify_key(kid)
      jwk = @key_fetcher.call(kid)
      raise Invalid, "unknown key" if jwk.blank?
      raise Invalid, "expired key" if jwk["expired_at"].present?

      JWT::JWK.import(jwk.slice("kty", "crv", "x", "y").transform_keys(&:to_sym)).verify_key
    end
  end
end
