require "rails_helper"

RSpec.describe "Page create actions" do
  let!(:household) { create(:household) }
  let(:owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, person: create(:person, household:)), owner:) }

  [
    [ "New invoice", -> { business_invoices_path(business) }, -> { new_business_invoice_path(business) } ],
    [ "New client", -> { business_clients_path(business) }, -> { new_business_client_path(business) } ],
    [ "Log a trip", -> { business_mileage_entries_path(business) }, -> { new_business_mileage_entry_path(business) } ],
    [ "Add manual transaction", -> { business_transactions_path(business) }, -> { new_business_transaction_path(business) } ],
    [ "New account", -> { business_accounts_path(business) }, -> { new_business_account_path(business) } ],
    [ "New category", -> { business_categories_path(business) }, -> { new_business_category_path(business) } ],
    [ "New rule", -> { business_rules_path(business) }, -> { new_business_rule_path(business) } ],
    [ "Invite someone", -> { business_memberships_path(business) }, -> { new_invite_path } ],
    [ "New business", -> { root_path }, -> { new_business_path } ],
    [ "Add a year", -> { tax_parameters_path }, -> { new_tax_parameter_path } ],
    [ "Add person", -> { people_path }, -> { new_person_path } ],
    [ "New invite", -> { invites_path }, -> { new_invite_path } ]
  ].each do |label, index_path, new_path|
    it "puts \"#{label}\" in the page header as a primary button" do
      sign_in_as owner
      get instance_exec(&index_path)
      page = Capybara.string(response.body)
      header = page.find("main header.page-header")
      expect(header).to have_css("h1")
      expect(header).to have_link(label, href: instance_exec(&new_path), class: %w[button primary])
      expect(page).to have_link(label, count: 1)
    end
  end
end
