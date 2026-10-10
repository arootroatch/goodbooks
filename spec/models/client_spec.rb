require "rails_helper"

RSpec.describe Client do
  it "requires a name unique within the business" do
    client = create(:client, name: "Acme")
    expect(build(:client, business: client.business, name: "Acme")).not_to be_valid
    expect(build(:client, name: "Acme")).to be_valid
    expect(build(:client, name: "")).not_to be_valid
  end

  it "accepts a blank email but rejects a malformed one" do
    expect(build(:client, email: "")).to be_valid
    expect(build(:client, email: "billing@acme.test")).to be_valid
    expect(build(:client, email: "not an email")).not_to be_valid
  end

  it "lists only active clients in the active scope" do
    active = create(:client)
    create(:client, business: active.business, archived_at: Time.current)
    expect(active.business.clients.active).to eq([ active ])
  end
end
