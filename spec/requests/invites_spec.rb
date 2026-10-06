require "rails_helper"

RSpec.describe "Invites" do
  let!(:business) { create(:business, name: "Pat Consulting") }
  let!(:other) { create(:business, name: "Jordan Studio") }

  it "lets a business owner create an invite and see the link once" do
    sign_in_as user_with_role("owner", business)
    post invites_path, params: { invite: { email: "acct@example.com", grant_roles: { business.id => "viewer" } } }
    expect(response).to have_http_status(:created)
    expect(response.body).to match(%r{/join/[\w-]{20,}})
  end

  it "rejects granting a business the creator doesn't own" do
    sign_in_as user_with_role("owner", business)
    post invites_path, params: { invite: { grant_roles: { other.id => "viewer" } } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "forbids users who own nothing" do
    sign_in_as user_with_role("editor", business)
    get new_invite_path
    expect(response).to have_http_status(:forbidden)
  end

  describe "accepting" do
    let(:invite) { create(:invite, business: business, role: "viewer", email: "new@example.com") }

    it "signs up a new user, grants access, and starts 2FA enrollment" do
      post join_path(invite.token), params: { user: {
        name: "Avery", email_address: "new@example.com", password: AuthHelpers::PASSWORD, password_confirmation: AuthHelpers::PASSWORD
      } }
      expect(response).to redirect_to(new_two_factor_setup_path)
      expect(User.find_by!(email_address: "new@example.com").membership_for(business)).to be_viewer
    end

    it "re-renders signup errors without consuming the invite" do
      post join_path(invite.token), params: { user: { name: "A", email_address: "new@example.com", password: "short", password_confirmation: "short" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(Invite.find_usable(invite.token)).to eq(invite)
    end

    it "adds access for a signed-in user" do
      user = create(:user)
      sign_in_as user
      post join_path(invite.token)
      expect(response).to redirect_to(root_path)
      expect(user.membership_for(business)).to be_viewer
    end

    it "shows not found for used or expired tokens" do
      invite.accept!(create(:user))
      get join_path(invite.token)
      expect(response).to have_http_status(:not_found)
      get join_path("nonsense")
      expect(response).to have_http_status(:not_found)
    end
  end
end
