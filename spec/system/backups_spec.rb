require "rails_helper"

RSpec.describe "Backups", js: true do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let(:dir) { BackupSnapshots.default_dir }

  before do
    FileUtils.rm_rf(dir)
    FileUtils.mkdir_p(dir)
    %w[2026-10-14 2026-10-15].each { File.write(File.join(dir, "goodbooks-#{_1}.sqlite3"), "x") }
  end

  after { FileUtils.rm_rf(dir) }

  it "shows snapshots, saves retention and fills the restore command with the chosen date" do
    system_sign_in_as owner
    open_settings_menu
    click_on "Backups"
    expect(page).to have_content("2026-10-15")
    expect(page).to have_content("2026-10-14")

    fill_in "Snapshots to keep", with: "30"
    click_on "Save"
    expect(page).to have_content("Retention saved.")
    expect(household.reload.backup_retention).to eq(30)

    expect(find("pre.restore-command")).to have_text("/data/backups/goodbooks-2026-10-15.sqlite3")
    select "2026-10-14", from: "Snapshot to restore"
    expect(find("pre.restore-command")).to have_text("/data/backups/goodbooks-2026-10-14.sqlite3")
  end
end
