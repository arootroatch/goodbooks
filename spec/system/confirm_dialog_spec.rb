require "rails_helper"

RSpec.describe "Confirm dialog", js: true do
  it "asks before archiving, and only archives once confirmed" do
    business = create(:business)
    client = create(:client, business:, name: "Acme")
    system_sign_in_as user_with_role("owner", business)
    visit business_clients_path(business)

    click_on "Archive"
    within("dialog.confirm-dialog[open]") do
      expect(page).to have_text("Archive this client? It will be hidden until you unarchive it.")
      click_on "Cancel"
    end
    expect(page).to have_no_css("dialog[open]")
    expect(client.reload).not_to be_archived

    click_on "Archive"
    within("dialog.confirm-dialog[open]") { click_on "Archive" }
    expect(page).to have_text("Client archived.")
    expect(client.reload).to be_archived
  end

  it "confirms an edit form's Delete button, which submits a separate form" do
    business = create(:business)
    entry = create(:mileage_entry, business:)
    system_sign_in_as user_with_role("editor", business)
    visit edit_business_mileage_entry_path(business, entry)

    click_on "Delete"
    within("dialog.confirm-dialog[open]") do
      expect(page).to have_text("Delete this trip?")
      click_on "Delete"
    end
    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_text("Trip deleted.")
    expect(MileageEntry.exists?(entry.id)).to be(false)
  end
end
