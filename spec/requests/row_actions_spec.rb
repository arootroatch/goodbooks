require "rails_helper"

RSpec.describe "Table row actions" do
  let!(:household) { create(:household) }
  let(:owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, person: create(:person, household:)), owner:) }

  before do
    create(:mileage_entry, business:, driven_on: Date.current)
    create(:transaction, account: business.accounts.first, posted_on: Date.current)
    create(:rule, business:)
    create(:tax_parameters)
    create(:invite, created_by: owner, business:)
    create(:membership, business:, role: "viewer")
    business.accounts.first.update!(source: "csv", csv_mapping: { "date_column" => "Date", "payee_column" => "Payee", "amount_column" => "Amount" })
  end

  [
    [ "mileage", -> { business_mileage_entries_path(business) }, %w[Edit] ],
    [ "transactions", -> { business_transactions_path(business) }, %w[Edit] ],
    [ "rules", -> { business_rules_path(business) }, %w[Edit Delete] ],
    [ "accounts", -> { business_accounts_path(business) }, [ "Import CSV", "Edit", "Archive" ] ],
    [ "tax parameters", -> { tax_parameters_path }, %w[Edit] ],
    [ "people", -> { people_path }, %w[Edit] ],
    [ "invites", -> { invites_path }, %w[Revoke] ],
    [ "members", -> { business_memberships_path(business) }, %w[Remove] ]
  ].each do |page, path, labels|
    it "groups #{labels.join(', ')} as buttons on #{page}" do
      sign_in_as owner
      get instance_exec(&path)
      group = Nokogiri::HTML(response.body).at_css("tbody td .button-group")
      expect(group).to be_present
      expect(group.css("a, button").map { _1.text.strip }).to eq(labels)
    end
  end
end
