require "rails_helper"

RSpec.describe AuditEvent do
  let(:event) { described_class.create!(user: create(:user), action: "summary", summary: "x") }

  it "can't be updated or destroyed" do
    expect { event.update!(summary: "y") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "filters by user, type, record, book and date range" do
    user = create(:user)
    old = travel_to(Date.new(2026, 1, 5).noon) { described_class.create!(user:, action: "create", auditable_type: "Rule", auditable_id: 1, business_id: 7) }
    recent = described_class.create!(user:, action: "update", auditable_type: "Goal", auditable_id: 2, business_id: 8)
    expect(described_class.filtered(user_id: user.id)).to contain_exactly(old, recent)
    expect(described_class.filtered(auditable_type: "Rule")).to eq([ old ])
    expect(described_class.filtered(auditable_type: "Goal", auditable_id: 2)).to eq([ recent ])
    expect(described_class.filtered(business_id: 8)).to eq([ recent ])
    expect(described_class.filtered(range: Date.new(2026, 1, 1)..Date.new(2026, 1, 31))).to eq([ old ])
  end
end
