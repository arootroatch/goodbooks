# spec/requests/audit_actors_spec.rb
require "rails_helper"

RSpec.describe "Audit actors" do
  it "attributes setup to the new owner" do
    post setup_path, params: { setup: { household_name: "Home", name: "Alex", email_address: "alex@example.com",
                                        password: AuthHelpers::PASSWORD, password_confirmation: AuthHelpers::PASSWORD } }
    owner = User.find_by!(email_address: "alex@example.com")
    expect(AuditEvent.where(user: owner).pluck(:auditable_type)).to include("Household", "Person")
  end

  it "attributes an invite accepted at sign-up to the new user" do
    business = create(:business)
    invite = create(:invite, business: business, role: "viewer")
    post join_path(token: invite.token), params: { user: { name: "Avery", email_address: "avery@example.com",
                                                           password: AuthHelpers::PASSWORD, password_confirmation: AuthHelpers::PASSWORD } }
    avery = User.find_by!(email_address: "avery@example.com")
    expect(AuditEvent.find_by!(auditable_type: "Membership")).to have_attributes(user_id: avery.id, action: "create")
  end

  it "writes one summary when an editor applies rules to the inbox" do
    business = create(:business)
    software = create(:category, business: business)
    create(:rule, business: business, value: "adobe", category: software)
    create_list(:transaction, 2, account: create(:account, business: business), payee: "ADOBE")
    sign_in_as user_with_role("editor", business)
    post apply_business_rules_path(business)
    expect(AuditEvent.pluck(:action, :summary)).to eq([ [ "summary", "Applied rules: 2 transactions categorized" ] ])
  end
end
