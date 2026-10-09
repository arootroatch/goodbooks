require "rails_helper"

RSpec.describe PlaidItem do
  it "encrypts the access token at rest and hides it from inspect" do
    item = create(:plaid_item, access_token: "access-sandbox-secret-123")
    raw = PlaidItem.connection.select_value("SELECT access_token FROM plaid_items WHERE id = #{item.id}")
    expect(raw).not_to include("access-sandbox-secret-123")
    expect(item.reload.access_token).to eq("access-sandbox-secret-123")
    expect(item.inspect).not_to include("access-sandbox-secret-123")
  end

  it "defaults to ok and validates status, item id, and institution" do
    item = create(:plaid_item)
    expect(item).to be_ok
    expect(build(:plaid_item, item_id: item.item_id)).not_to be_valid
    expect(build(:plaid_item, institution_name: "")).not_to be_valid
    expect { item.status = "bogus" }.not_to raise_error
    expect(item).not_to be_valid
  end

  it "is manageable by its creator and the household owner only" do
    creator = create(:user)
    owner = create(:user, :household_owner)
    other = create(:user)
    item = create(:plaid_item, created_by: creator)
    expect(PlaidItem.manageable_by(creator)).to eq([ item ])
    expect(PlaidItem.manageable_by(owner)).to eq([ item ])
    expect(PlaidItem.manageable_by(other)).to be_empty
    expect(item.manageable_by?(owner)).to be(true)
    expect(item.manageable_by?(other)).to be(false)
  end

  it "enqueues a sync for every connected item, and nothing when Plaid is disabled" do
    ok = create(:plaid_item)
    create(:plaid_item, status: "login_required")
    create(:plaid_item, status: "error")
    expect { PlaidItem.sync_all_later }.to have_enqueued_job(PlaidSyncJob).with(ok).exactly(:once)
    PlaidGateway.current = nil
    expect { PlaidItem.sync_all_later }.not_to have_enqueued_job(PlaidSyncJob)
  end
end
