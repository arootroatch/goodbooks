module User::TwoFactor
  extend ActiveSupport::Concern

  RECOVERY_CODE_COUNT = 10

  included do
    encrypts :otp_secret
  end

  def otp_enabled? = otp_enabled_at.present?

  def totp = ROTP::TOTP.new(otp_secret, issuer: "goodbooks")

  def otp_provisioning_uri = totp.provisioning_uri(email_address)

  def generate_otp_secret!
    update!(otp_secret: ROTP::Base32.random)
  end

  def verify_otp(code)
    return false if otp_secret.blank? || code.blank?

    with_lock do
      timestamp = totp.verify(code.to_s.gsub(/\s/, ""), drift_behind: 30, after: otp_last_verified_at)
      next false unless timestamp

      update!(otp_last_verified_at: timestamp)
      true
    end
  end

  def enable_otp!
    codes = Array.new(RECOVERY_CODE_COUNT) { SecureRandom.alphanumeric(10).downcase }
    update!(otp_enabled_at: Time.current, recovery_code_digests: codes.map { |c| BCrypt::Password.create(c, cost: bcrypt_cost) })
    codes
  end

  def consume_recovery_code(code)
    normalized = code.to_s.strip.downcase
    return false if normalized.empty?

    with_lock do
      digest = recovery_code_digests.find { |d| BCrypt::Password.new(d) == normalized }
      next false unless digest

      update!(recovery_code_digests: recovery_code_digests - [ digest ])
      true
    end
  end

  private

  def bcrypt_cost
    ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
  end
end
