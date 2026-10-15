require "rails_helper"

RSpec.describe "Sessions list" do
  before { create(:household) }

  let(:user) { create(:user) }
  let!(:phone) do
    user.sessions.create!(user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Version/18.0 Mobile Safari/604.1", ip_address: "10.0.0.9")
  end

  it "lists the user's sessions with the current one marked" do
    sign_in_as user
    get session_records_path
    expect(response.body).to include("Safari on iOS", "10.0.0.9", "This device")
  end

  it "revokes another session" do
    sign_in_as user
    delete session_record_path(phone)
    expect(Session.exists?(phone.id)).to be(false)
    expect(response).to redirect_to(session_records_path)
  end

  it "treats revoking the current session as signing out" do
    sign_in_as user
    delete session_record_path(user.sessions.where.not(id: phone.id).last)
    expect(response).to redirect_to(new_session_path)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "revokes every other session" do
    sign_in_as user
    delete others_session_records_path
    expect(user.sessions.count).to eq(1)
    expect(Session.exists?(phone.id)).to be(false)
  end

  it "returns 404 for someone else's session" do
    sign_in_as create(:user)
    delete session_record_path(phone)
    expect(response).to have_http_status(:not_found)
    expect(Session.exists?(phone.id)).to be(true)
  end
end
