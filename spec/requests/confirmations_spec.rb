require "rails_helper"

RSpec.describe "Confirming destructive buttons" do
  let!(:household) { create(:household) }
  let(:owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, person: create(:person, household:)), owner:) }
  let!(:client) { create(:client, business:) }
  let!(:rule) { create(:rule, business:) }
  let!(:entry) { create(:mileage_entry, business:) }
  let!(:txn) { create(:transaction, account: business.accounts.first) }
  let!(:draft) { create(:invoice, business:, client:, status: "draft") }
  let!(:payment) { create(:invoice_payment, invoice: create(:invoice, business:, client:)) }

  before do
    create(:invite, created_by: owner, business:)
    create(:membership, business:, role: "viewer")
  end

  def confirm_for(label)
    form = Capybara.string(response.body).first(:button, label).ancestor("form")
    form["data-turbo-confirm"]
  end

  [
    [ "Archive", "client list", -> { business_clients_path(business) } ],
    [ "Delete", "rule list", -> { business_rules_path(business) } ],
    [ "Revoke", "invite list", -> { invites_path } ],
    [ "Remove", "member list", -> { business_memberships_path(business) } ],
    [ "Delete", "trip edit", -> { edit_business_mileage_entry_path(business, entry) } ],
    [ "Delete", "transaction edit", -> { edit_business_transaction_path(business, txn) } ],
    [ "Void", "invoice", -> { business_invoice_path(business, draft) } ],
    [ "Delete", "invoice", -> { business_invoice_path(business, draft) } ],
    [ "Unlink", "invoice payments", -> { business_invoice_path(business, payment.invoice) } ]
  ].each do |label, page_name, path|
    it "asks before \"#{label}\" on the #{page_name} page" do
      sign_in_as owner
      get instance_exec(&path)
      expect(confirm_for(label)).to be_present
    end
  end

  it "does not ask before Unarchive" do
    client.update!(archived_at: Time.current)
    sign_in_as owner
    get business_clients_path(business, archived: "1")
    expect(confirm_for("Unarchive")).to be_nil
  end
end
