require "rails_helper"

RSpec.describe "Authentication" do
  before { create(:household) }

  let(:user) { create(:user) }

  def log_in_password(email: user.email_address, password: AuthHelpers::PASSWORD)
    post session_path, params: { email_address: email, password: password }
  end

  it "redirects anonymous visitors to the login page" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "rejects a wrong password" do
    log_in_password(password: "wrong password!!")
    expect(response).to redirect_to(new_session_path)
  end

  it "shows the login failure message exactly once" do
    log_in_password(password: "wrong password!!")
    follow_redirect!
    alert = flash[:alert]
    expect(alert).to be_present
    expect(response.body.scan(alert).size).to eq(1)
  end

  it "requires a TOTP code after the password" do
    log_in_password
    expect(response).to redirect_to(new_two_factor_path)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "signs in after a correct code" do
    log_in_password
    post two_factor_path, params: { code: user.totp.now }
    expect(response).to redirect_to(root_url)
    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "rejects a wrong code" do
    log_in_password
    wrong = user.totp.now == "000000" ? "111111" : "000000"
    post two_factor_path, params: { code: wrong }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "does not try recovery codes for a wrong 6-digit code" do
    log_in_password
    wrong = user.totp.now == "000000" ? "111111" : "000000"
    expect_any_instance_of(User).not_to receive(:consume_recovery_code)
    post two_factor_path, params: { code: " #{wrong[0, 3]} #{wrong[3, 3]} " }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects a replayed code on a second login in the same window" do
    freeze_time do
      code = user.totp.now
      log_in_password
      post two_factor_path, params: { code: code }
      delete session_path
      log_in_password
      post two_factor_path, params: { code: code }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "accepts a recovery code once" do
    codes = user.enable_otp!
    log_in_password
    post two_factor_path, params: { code: codes.first }
    expect(response).to redirect_to(root_url)
    delete session_path
    log_in_password
    post two_factor_path, params: { code: codes.first }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects and destroys sessions older than 30 days even if the cookie survives" do
    sign_in_as(user)
    get root_path
    expect(response).to have_http_status(:ok)
    Session.update_all(created_at: 31.days.ago)
    get root_path
    expect(response).to redirect_to(new_session_path)
    expect(Session.count).to eq(0)
  end

  it "sets the session cookie to expire in about 30 days" do
    log_in_password
    post two_factor_path, params: { code: user.totp.now }
    cookie = Array(response.headers["set-cookie"]).flat_map(&:lines).find { |l| l.start_with?("session_id=") }
    expires = Time.httpdate(cookie[/expires=([^;]+)/i, 1])
    expect(expires).to be_within(1.minute).of(30.days.from_now)
    expect(cookie).to match(/httponly/i)
  end

  it "rotates the Rails session id at the password step while keeping the return-to path" do
    get root_path
    get new_session_path
    before_id = session.id.to_s
    log_in_password
    expect(session[:return_to_after_authenticating]).to be_present
    expect(session.id.to_s).not_to eq(before_id)
  end

  it "expires the pending login after 10 minutes" do
    log_in_password
    travel 11.minutes
    post two_factor_path, params: { code: user.totp.now }
    expect(response).to redirect_to(new_session_path)
  end

  it "does not allow the code page without a password step" do
    get new_two_factor_path
    expect(response).to redirect_to(new_session_path)
  end

  describe "rate limiting" do
    include_context "with rate limiting"

    let(:wrong) { user.totp.now == "000000" ? "111111" : "000000" }

    it "limits password attempts per IP on the sessions controller" do
      10.times { log_in_password(password: "wrong password!!") }
      expect(response).to redirect_to(new_session_path)
      log_in_password(password: "wrong password!!")
      expect(flash[:alert]).to eq("Try again later.")
    end

    it "limits code attempts per pending user across IPs" do
      log_in_password
      10.times { |i| post two_factor_path, params: { code: wrong }, headers: { "REMOTE_ADDR" => "10.0.0.#{i + 1}" } }
      expect(response).to have_http_status(:unprocessable_content)
      post two_factor_path, params: { code: wrong }, headers: { "REMOTE_ADDR" => "10.0.1.1" }
      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq("Try again later.")
    end

    it "limits code attempts per pending user on setup" do
      user = create(:user, :without_otp)
      post session_path, params: { email_address: user.email_address, password: AuthHelpers::PASSWORD }
      get new_two_factor_setup_path
      10.times { |i| post two_factor_setup_path, params: { code: "abcdef" }, headers: { "REMOTE_ADDR" => "10.0.0.#{i + 1}" } }
      expect(response).to redirect_to(new_two_factor_setup_path)
      post two_factor_setup_path, params: { code: "abcdef" }, headers: { "REMOTE_ADDR" => "10.0.1.1" }
      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq("Try again later.")
    end
  end

  describe "first-time enrollment" do
    let(:user) { create(:user, :without_otp) }

    it "sends a user without 2FA to setup, then signs them in with recovery codes shown" do
      log_in_password
      expect(response).to redirect_to(new_two_factor_setup_path)
      get new_two_factor_setup_path
      expect(response.body).to include("<svg")
      user.reload
      post two_factor_setup_path, params: { code: user.totp.now }
      expect(response).to have_http_status(:ok)
      expect(response.body.scan(/<li class="recovery-code">/).size).to eq(10)
      expect(user.reload).to be_otp_enabled
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "keeps the same secret across setup page reloads" do
      log_in_password
      get new_two_factor_setup_path
      secret = user.reload.otp_secret
      get new_two_factor_setup_path
      expect(user.reload.otp_secret).to eq(secret)
    end

    it "issues a fresh secret on each password login until enrolled" do
      log_in_password
      get new_two_factor_setup_path
      first_secret = user.reload.otp_secret
      log_in_password
      get new_two_factor_setup_path
      expect(user.reload.otp_secret).not_to eq(first_secret)
    end

    it "rejects a wrong setup code" do
      log_in_password
      get new_two_factor_setup_path
      post two_factor_setup_path, params: { code: "abcdef" }
      expect(response).to redirect_to(new_two_factor_setup_path)
      expect(user.reload).not_to be_otp_enabled
    end
  end

  it "keeps enrolled users out of setup" do
    log_in_password
    get new_two_factor_setup_path
    expect(response).to redirect_to(new_session_path)
  end
end
