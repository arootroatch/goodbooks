require "rails_helper"

RSpec.describe Session do
  let(:session) { create(:user).sessions.create! }

  it "starts with last_seen_at set" do
    expect(session.last_seen_at).to be_within(1.second).of(Time.current)
  end

  it "refreshes last_seen_at at most every five minutes without touching updated_at" do
    seen = session.last_seen_at
    travel 4.minutes do
      session.seen!
      expect(session.reload.last_seen_at).to eq(seen)
    end
    travel 6.minutes do
      expect { session.seen! }.not_to(change { session.reload.updated_at })
      expect(session.reload.last_seen_at).to be > seen
    end
  end
end
