require "rails_helper"

RSpec.describe "Audit log" do
  let!(:business) { create(:business, name: "Smith Photography") }
  let!(:owner) { create(:user, :household_owner, name: "Alex") }
  let!(:editor) { user_with_role("editor", business, name: "Whitney") }

  it "is forbidden to everyone but the household owner" do
    sign_in_as editor
    get audit_events_path
    expect(response).to have_http_status(:forbidden)
  end

  it "lists events newest first with who, what and the change" do
    rule = Audit.as(editor) { create(:rule, business: business, value: "stripe") }
    Audit.as(owner) { rule.update!(value: "square") }
    sign_in_as owner
    get audit_events_path
    expect(response.body).to match(/Alex.*updated.*Whitney.*created/m)
    expect(response.body).to include("Smith Photography", "stripe", "square")
  end

  it "filters by user and record type, and links a label to its history" do
    Audit.as(editor) { create(:rule, business: business) }
    Audit.as(owner) { create(:client, business: business, name: "Acme") }
    sign_in_as owner
    get audit_events_path(user_id: owner.id)
    expect(response.body).to include("Acme")
    expect(response.body).not_to include("Rule: payee")
    get audit_events_path(auditable_type: "Rule")
    expect(response.body).to include("Rule: payee")
    expect(response.body).to include(ERB::Util.html_escape(audit_events_path(auditable_type: "Rule", auditable_id: Rule.last.id)))
  end

  it "filters removal summary events by the User type without leaking other types with the same id" do
    other = Audit.as(owner) { create(:client, business: business, name: "Acme") }
    Audit.as(owner) { Audit.note("Removed Whitney from the household", record: editor) }
    event = AuditEvent.find_by!(auditable_type: "User")
    AuditEvent.where(auditable_type: "Client").update_all(auditable_id: event.auditable_id)
    sign_in_as owner
    get audit_events_path(auditable_type: "User", auditable_id: event.auditable_id)
    expect(response.body).to include("Removed Whitney from the household")
    expect(response.body).not_to include("Acme")
  end

  it "pages 50 at a time" do
    Audit.as(owner) { 51.times { |i| Audit.note("Event #{i}") } }
    sign_in_as owner
    get audit_events_path
    expect(response.body).to include("Event 50", "Event 1")
    expect(response.body).not_to include("Event 0<")
    older = AuditEvent.order(:id).second.id
    expect(response.body).to include(audit_events_path(before: older))
    get audit_events_path(before: older)
    expect(response.body).to include("Event 0")
  end

  it "shows a record's full history from its link, while the default view is year-to-date" do
    client = travel_to(Date.new(2025, 6, 1)) { Audit.as(owner) { create(:client, business: business, name: "Old Acme") } }
    sign_in_as owner
    get audit_events_path
    expect(response.body).not_to include("Old Acme")
    get audit_events_path(auditable_type: "Client", auditable_id: client.id)
    expect(response.body).to include("Old Acme")
  end
end
