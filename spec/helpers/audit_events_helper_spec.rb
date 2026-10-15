require "rails_helper"

RSpec.describe AuditEventsHelper do
  it "formats money, booleans, blanks, lists and filtered values" do
    expect(helper.audit_value("amount_cents", -1250)).to eq(Money.new(-1250).to_s)
    expect(helper.audit_value("transfer", true)).to eq("Yes")
    expect(helper.audit_value("transfer", false)).to eq("No")
    expect(helper.audit_value("memo", nil)).to eq("—")
    expect(helper.audit_value("grants", [ "A: viewer", "B: editor" ])).to eq("A: viewer, B: editor")
    expect(helper.audit_value("token_digest", "[FILTERED]")).to eq("[FILTERED]")
  end

  it "describes the action" do
    expect(helper.audit_action(AuditEvent.new(action: "destroy"))).to eq("deleted")
    expect(helper.audit_action(AuditEvent.new(action: "summary", summary: "Reordered rules"))).to eq("Reordered rules")
  end
end
