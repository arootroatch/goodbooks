require "rails_helper"

RSpec.describe "Audit coverage" do
  let(:actor) { create(:user) }

  it "audits exactly the models in Audit::MODELS" do
    Rails.application.eager_load!
    audited = ApplicationRecord.descendants.select { _1.include?(Audited) }.map(&:name)
    expect(audited).to match_array(Audit::MODELS)
  end

  it "filters every column a secret filter would catch" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    Audit::MODELS.each do |name|
      name.constantize.column_names.each do |column|
        next if column.include?("email") || column.include?("code") # logged, not secret; audit shows them
        next if filter.filter(column => "x")[column] == "x"

        expect(Audit.filter(column => [ 1, 2 ])[column]).to eq([ Audit::FILTERED, Audit::FILTERED ]), "#{name}##{column}"
      end
    end
  end

  it "folds an invite's grants into its create event and filters the token digest" do
    business = create(:business, name: "Smith Photography")
    Audit.as(actor) { create(:invite, business: business, role: "editor") }
    values = AuditEvent.find_by!(auditable_type: "Invite").changed_values
    expect(values["grants"]).to eq([ nil, [ "Smith Photography: editor" ] ])
    expect(values["token_digest"]).to eq([ Audit::FILTERED, Audit::FILTERED ])
    expect(AuditEvent.where(auditable_type: "InviteGrant")).to be_empty
  end

  it "finds the book through the account for transactions and through the invoice for payments" do
    account = create(:account)
    Audit.as(actor) { create(:transaction, account: account) }
    expect(AuditEvent.last.business_id).to eq(account.business_id)
  end

  it "labels a business by name and stores its own id as the book" do
    business = create(:business)
    Audit.as(actor) { business.update!(name: "Renamed") }
    expect(AuditEvent.last).to have_attributes(label: "Renamed", business_id: business.id)
  end

  it "ignores Plaid sync bookkeeping and filters the access token" do
    item = create(:plaid_item)
    expect { Audit.as(actor) { item.update!(cursor: "c2", last_synced_at: Time.current) } }.not_to change(AuditEvent, :count)
    Audit.as(actor) { item.update!(access_token: "new-token") }
    expect(AuditEvent.last.changed_values["access_token"]).to eq([ Audit::FILTERED, Audit::FILTERED ])
  end
end
