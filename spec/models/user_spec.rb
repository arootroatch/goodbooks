require "rails_helper"

RSpec.describe User do
  describe "validations" do
    it "requires a password of at least 12 characters" do
      user = build(:user, password: "short")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "normalizes the email address" do
      expect(create(:user, email_address: " Pat@Example.COM ").email_address).to eq("pat@example.com")
    end

    it "requires a name" do
      expect(build(:user, name: "")).not_to be_valid
    end
  end

  describe "#verify_otp" do
    let(:user) { create(:user) }

    it "accepts the current code" do
      expect(user.verify_otp(user.totp.now)).to be(true)
    end

    it "rejects a wrong code" do
      wrong = user.totp.now == "000000" ? "111111" : "000000"
      expect(user.verify_otp(wrong)).to be(false)
    end

    it "rejects a replayed code" do
      freeze_time do
        code = user.totp.now
        expect(user.verify_otp(code)).to be(true)
        expect(user.reload.verify_otp(code)).to be(false)
      end
    end

    it "rejects when no secret is set" do
      expect(build(:user, :without_otp).verify_otp("123456")).to be(false)
    end
  end

  describe "#enable_otp! and recovery codes" do
    let(:user) { create(:user, :without_otp, otp_secret: ROTP::Base32.random) }

    it "enables 2FA and returns 10 single-use recovery codes" do
      codes = user.enable_otp!
      expect(user.reload).to be_otp_enabled
      expect(codes.size).to eq(10)
      expect(codes.uniq.size).to eq(10)
      expect(user.consume_recovery_code(codes.first.upcase)).to be(true)
      expect(user.reload.consume_recovery_code(codes.first)).to be(false)
      expect(user.recovery_code_digests.size).to eq(9)
    end

    it "does not store recovery codes in plain text" do
      codes = user.enable_otp!
      expect(user.reload.recovery_code_digests).not_to include(codes.first)
    end
  end

  it "encrypts the OTP secret at rest" do
    user = create(:user)
    raw = User.connection.select_value("SELECT otp_secret FROM users WHERE id = #{user.id}")
    expect(raw).not_to eq(user.otp_secret)
  end
end
