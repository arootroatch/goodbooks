# Production secrets from docker-compose.yml's environment, else from config/credentials.yml.enc. A blank value counts as unset.
# SECRET_KEY_BASE_DUMMY is set only while the Docker image precompiles assets, which needs none of them.
module Secrets
  ENCRYPTION_KEYS = %i[primary_key deterministic_key key_derivation_salt].freeze

  def self.secret_key_base!(env = ENV, credentials = Rails.application.credentials)
    return if env["SECRET_KEY_BASE_DUMMY"].present?

    env["SECRET_KEY_BASE"].presence || credentials.dig(:secret_key_base).presence or raise missing([ "SECRET_KEY_BASE" ])
  end

  # Active Record encryption keys: they decrypt stored 2FA secrets and Plaid tokens.
  def self.encryption_keys!(env = ENV, credentials = Rails.application.credentials)
    return {} if env["SECRET_KEY_BASE_DUMMY"].present?

    keys = ENCRYPTION_KEYS.to_h { [ _1, env[variable(_1)].presence || credentials.dig(:active_record_encryption, _1).presence ] }
    unset = keys.select { |_, value| value.nil? }.keys
    raise missing(unset.map { variable(_1) }) if unset.any?

    keys
  end

  def self.variable(key) = "ACTIVE_RECORD_ENCRYPTION_#{key.upcase}"

  def self.missing(names) = "#{names.join(", ")} not set. Set #{names.one? ? "it" : "them"} in docker-compose.yml (see README)."
end
