require "rails_helper"

RSpec.describe User do
  it "lists the active books (business or personal) the user owns" do
    user = create(:user)
    owned = create(:business)
    personal = create(:business, :personal)
    edited = create(:business)
    archived = create(:business, archived_at: Time.current)
    create(:membership, user: user, business: owned, role: "owner")
    create(:membership, user: user, business: personal, role: "owner")
    create(:membership, user: user, business: edited, role: "editor")
    create(:membership, user: user, business: archived, role: "owner")
    expect(user.owned_books).to contain_exactly(owned, personal)
  end
end
