module AuthHelpers
  PASSWORD = "correct horse battery"

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: PASSWORD }
    post two_factor_path, params: { code: user.totp.now }
  end
end

module SystemAuthHelpers
  def system_sign_in_as(user)
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: AuthHelpers::PASSWORD
    click_on "Sign in"
    fill_in "code", with: user.totp.now
    click_on "Verify"
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
  config.include SystemAuthHelpers, type: :system
end
