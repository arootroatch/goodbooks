require "rails_helper"

RSpec.describe "First-run setup" do
  let(:params) do
    { setup: { household_name: "Our House", name: "Pat", email_address: "pat@example.com",
               password: AuthHelpers::PASSWORD, password_confirmation: AuthHelpers::PASSWORD, spouse_name: "Jordan" } }
  end

  it "redirects every page to setup until a household exists" do
    get root_path
    expect(response).to redirect_to(new_setup_path)
    get new_session_path
    expect(response).to redirect_to(new_setup_path)
  end

  it "creates the household and sends the owner to 2FA enrollment" do
    post setup_path, params: params
    expect(response).to redirect_to(new_two_factor_setup_path)
    expect(User.sole).to be_household_owner
  end

  it "re-renders with errors" do
    post setup_path, params: params.deep_merge(setup: { password: "short", password_confirmation: "short" })
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "is gone once a household exists" do
    create(:household)
    get new_setup_path
    expect(response).to have_http_status(:not_found)
    post setup_path, params: params
    expect(response).to have_http_status(:not_found)
  end
end
