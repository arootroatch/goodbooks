require "rails_helper"

RSpec.describe Audit do
  let(:business) { create(:business) }
  let(:actor) { create(:user, name: "Alex") }

  it "writes nothing without an actor" do
    expect { create(:rule, business: business) }.not_to change(AuditEvent, :count)
  end

  it "records a create with the new values, the label and the book" do
    rule = Audit.as(actor) { create(:rule, business: business, value: "stripe") }
    event = AuditEvent.last
    expect(event).to have_attributes(user: actor, action: "create", auditable_type: "Rule", auditable_id: rule.id,
                                     business_id: business.id, label: "Rule: payee contains \"stripe\"")
    expect(event.changed_values["value"]).to eq([ nil, "stripe" ])
    expect(event.changed_values.keys).not_to include("id", "created_at", "updated_at")
  end

  it "records an update with before and after, and skips an update that changed nothing tracked" do
    rule = create(:rule, business: business, value: "adobe")
    Audit.as(actor) { rule.update!(value: "figma") }
    expect(AuditEvent.last.changed_values).to eq("value" => [ "adobe", "figma" ])
    expect { Audit.as(actor) { rule.touch } }.not_to change(AuditEvent, :count)
    expect { Audit.as(actor) { rule.save! } }.not_to change(AuditEvent, :count)
  end

  it "records a destroy with the old values" do
    rule = create(:rule, business: business, value: "adobe")
    Audit.as(actor) { rule.destroy! }
    expect(AuditEvent.last).to have_attributes(action: "destroy", auditable_id: rule.id)
    expect(AuditEvent.last.changed_values["value"]).to eq([ "adobe", nil ])
  end

  it "filters secret-looking attribute names" do
    expect(Audit.filter("token_digest" => [ nil, "abc" ], "access_token" => [ "a", "b" ], "email" => [ nil, "x@y.z" ]))
      .to eq("token_digest" => [ "[FILTERED]", "[FILTERED]" ], "access_token" => [ "[FILTERED]", "[FILTERED]" ], "email" => [ nil, "x@y.z" ])
  end

  it "scopes the actor override to the block" do
    Audit.as(actor) { expect(Current.actor).to eq(actor) }
    expect(Current.actor).to be_nil
  end

  describe ".summarize" do
    it "writes one summary event instead of per-row events, and returns the block's value" do
      business
      result = Audit.as(actor) do
        Audit.summarize(business: business) do |summary|
          create(:rule, business: business)
          create(:rule, business: business)
          summary.text = "Did two things"
          :done
        end
      end
      expect(result).to eq(:done)
      expect(AuditEvent.pluck(:action, :summary, :business_id)).to eq([ [ "summary", "Did two things", business.id ] ])
    end

    it "writes only the outermost summary when nested" do
      Audit.as(actor) do
        Audit.summarize do |outer|
          Audit.summarize { |inner| inner.text = "inner" }
          outer.text = "outer"
        end
      end
      expect(AuditEvent.pluck(:summary)).to eq([ "outer" ])
    end

    it "writes nothing when the block raises" do
      expect do
        Audit.as(actor) { Audit.summarize { |s| s.text = "x"; raise "boom" } }
      end.to raise_error("boom")
      expect(AuditEvent.count).to eq(0)
    end

    it "writes nothing without an actor, and still suppresses rows" do
      Audit.summarize { |s| create(:rule, business: business); s.text = "x" }
      expect(AuditEvent.count).to eq(0)
    end

    it "labels the summary with its record" do
      rule = create(:rule, business: business, value: "adobe")
      Audit.as(actor) { Audit.summarize(record: rule) { |s| s.text = "Reordered rules" } }
      expect(AuditEvent.last).to have_attributes(auditable_type: "Rule", auditable_id: rule.id, business_id: business.id,
                                                 label: "Rule: payee contains \"adobe\"")
    end
  end

  describe ".note" do
    it "labels a non-audited record by its name" do
      target = create(:user, name: "Avery")
      Audit.as(actor) { Audit.note("Removed Avery from the household", record: target) }
      expect(AuditEvent.last).to have_attributes(action: "summary", auditable_type: "User", auditable_id: target.id, label: "Avery", business_id: nil)
    end
  end
end
