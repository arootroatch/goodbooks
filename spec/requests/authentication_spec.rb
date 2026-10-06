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
