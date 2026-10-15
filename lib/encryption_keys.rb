module EncryptionKeys
  NAMES = %i[primary_key deterministic_key key_derivation_salt].freeze

  # Active Record encryption keys (2FA secrets, Plaid tokens) from ACTIVE_RECORD_ENCRYPTION_*, else from
  # config/credentials.yml.enc. SECRET_KEY_BASE_DUMMY is set only while the Docker image precompiles assets.
  def self.fetch!(env = ENV, credentials = Rails.application.credentials)
    return {} if env["SECRET_KEY_BASE_DUMMY"].present?

    keys = NAMES.to_h { [ _1, env[variable(_1)].presence || credentials.dig(:active_record_encryption, _1).presence ] }
    missing = keys.select { |_, value| value.nil? }.keys
    raise "#{missing.map { variable(_1) }.join(", ")} not set. Set them in docker-compose.yml (see README)." if missing.any?

    keys
  end

  def self.variable(name) = "ACTIVE_RECORD_ENCRYPTION_#{name.upcase}"
end
