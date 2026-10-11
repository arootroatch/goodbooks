require "rails_helper"

RSpec.describe "Archiving from the list" do
  let!(:business) { create(:business) }

  {
    "clients" => { factory: :client, role: "editor", path: :business_clients_path },
    "accounts" => { factory: :account, role: "owner", path: :business_accounts_path },
    "categories" => { factory: :category, role: "editor", path: :business_categories_path }
  }.each do |name, config|
    describe name do
      let!(:record) { create(config[:factory], business: business) }
      let(:singular) { name.singularize }

      def member_path(action, record) = public_send(:"#{action}_business_#{record.model_name.singular}_path", business, record)

      it "archives and unarchives from row buttons" do
        sign_in_as user_with_role(config[:role], business)
        patch member_path(:archive, record)
        expect(response).to redirect_to(public_send(config[:path], business))
        expect(record.reload).to be_archived
        patch member_path(:unarchive, record)
        expect(record.reload).not_to be_archived
      end

      it "shows Edit and Archive as a button group, with no archived checkbox on the edit form" do
        sign_in_as user_with_role(config[:role], business)
        get public_send(config[:path], business, archived: "1")
        group = Nokogiri::HTML(response.body).at_css("##{ActionView::RecordIdentifier.dom_id(record)} .button-group")
        expect(group.css("a").map(&:text)).to include("Edit")
        expect(group.css("button").map(&:text)).to eq([ "Archive" ])
        get public_send(:"edit_business_#{singular}_path", business, record)
        expect(response.body).not_to include("#{singular}[archived]")
      end

      it "offers Unarchive for archived rows" do
        record.update!(archived_at: Time.current)
        sign_in_as user_with_role(config[:role], business)
        get public_send(config[:path], business, archived: "1")
        group = Nokogiri::HTML(response.body).at_css("##{ActionView::RecordIdentifier.dom_id(record)} .button-group")
        expect(group.css("button").map(&:text)).to eq([ "Unarchive" ])
      end

      it "forbids viewers" do
        sign_in_as user_with_role("viewer", business)
        patch member_path(:archive, record)
        expect(response).to have_http_status(:forbidden)
        expect(record.reload).not_to be_archived
      end
    end
  end
end
