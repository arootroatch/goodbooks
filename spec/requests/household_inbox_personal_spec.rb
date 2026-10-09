require "rails_helper"

RSpec.describe "Review rows from the personal book" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:personal) { PersonalBookProvisioner.call(household) }
  let!(:shop) { create(:business, name: "Pat Consulting") }
  let!(:accountant) { user_with_role("viewer", shop) }

  before do
    create(:membership, user: owner, business: shop, role: "owner")
    create(:transaction, account: create(:account, business: personal), payee: "PERSONAL FLAGGED", review_reason: "removed_by_bank")
    create(:transaction, account: create(:account, business: shop), payee: "SHOP FLAGGED", review_reason: "removed_by_bank")
  end

  it "hides them from the household inbox and the dashboard count for someone outside the personal book" do
    sign_in_as accountant
    get household_inbox_path
    expect(response.body).to include("SHOP FLAGGED")
    expect(response.body).not_to include("PERSONAL FLAGGED")
    get root_path
    expect(response.body).to include("Pat Consulting: 1 transaction")
    expect(response.body).not_to include("Personal: 1 transaction")
  end

  it "shows them to a member of the personal book" do
    sign_in_as owner
    get household_inbox_path
    expect(response.body).to include("PERSONAL FLAGGED", "SHOP FLAGGED")
    get root_path
    expect(response.body).to include("Personal: 1 transaction", "Pat Consulting: 1 transaction")
  end

  it "leaves archived books out of the dashboard count, like the household inbox" do
    shop.update!(archived_at: Time.current)
    sign_in_as owner
    get root_path
    expect(response.body).not_to include("Pat Consulting: 1 transaction")
    expect(response.body).to include("Personal: 1 transaction")
  end
end
