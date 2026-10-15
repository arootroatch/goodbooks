require "rails_helper"

RSpec.describe "Errors" do
  let!(:owner) { create(:user, :household_owner) }
  let!(:event) do
    ErrorEvent.create!(fingerprint: "f", error_class: "RuntimeError", message: "boom", backtrace: "app/models/x.rb:1",
                       source: "InvoicesController#create", occurrences: 3, first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago)
  end

  before { create(:household) }

  it "is forbidden to everyone but the household owner" do
    sign_in_as create(:user)
    get error_events_path
    expect(response).to have_http_status(:forbidden)
  end

  it "lists open errors, shows a sidebar badge, and resolves and reopens them" do
    sign_in_as owner
    get error_events_path
    expect(response.body).to include("RuntimeError", "boom", "InvoicesController#create", "app/models/x.rb:1")
    expect(response.body).to match(%r{Errors <span class="badge">1</span>})
    patch resolve_error_event_path(event)
    expect(event.reload.resolved_at).to be_present
    get error_events_path
    expect(response.body).not_to include("boom")
    get error_events_path(tab: "resolved")
    expect(response.body).to include("boom")
    patch reopen_error_event_path(event, tab: "resolved")
    expect(event.reload.resolved_at).to be_nil
  end
end
