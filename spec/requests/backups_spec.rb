require "rails_helper"

RSpec.describe "Backups" do
  include ActiveJob::TestHelper

  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let(:dir) { BackupSnapshots.default_dir }

  before { FileUtils.rm_rf(dir) }
  after { FileUtils.rm_rf(dir) }

  def write_snapshot(date, mtime: Time.current)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "goodbooks-#{date}.sqlite3")
    File.write(path, "snapshot #{date}")
    File.utime(mtime.to_time, mtime.to_time, path)
  end

  describe "access" do
    it "is forbidden to everyone but the household owner" do
      write_snapshot("2026-10-15")
      sign_in_as create(:user)
      get backups_path
      expect(response).to have_http_status(:forbidden)
      post backups_path
      expect(response).to have_http_status(:forbidden)
      patch backups_path, params: { household: { backup_retention: 3 } }
      expect(response).to have_http_status(:forbidden)
      get backup_download_path("goodbooks-2026-10-15.sqlite3")
      expect(response).to have_http_status(:forbidden)
    end

    it "shows the sidebar link only to the household owner" do
      sign_in_as owner
      get backups_path
      expect(response.body).to include(%(href="#{backups_path}"))
    end

    it "hides the sidebar link from non-owners" do
      sign_in_as user_with_role("owner", create(:business))
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(%(href="#{backups_path}"))
    end
  end

  describe "show" do
    before { sign_in_as owner }

    it "lists snapshots newest first with their size and the last backup time" do
      write_snapshot("2026-10-14", mtime: 2.days.ago)
      write_snapshot("2026-10-15", mtime: 2.hours.ago)
      get backups_path
      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Last backup:", "Keeping 14", "19 Bytes")
      expect(body.index("2026-10-15")).to be < body.index("2026-10-14")
      expect(body).to include(backup_download_path("goodbooks-2026-10-15.sqlite3"))
      expect(body).not_to include("No backup in the last day")
    end

    it "warns when there are no backups, including when the directory doesn't exist" do
      get backups_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No backups yet.")
    end

    it "warns when the newest backup is overdue and links an open backup error" do
      write_snapshot("2026-10-13", mtime: 3.days.ago)
      ErrorEvent.create!(fingerprint: "b", error_class: "SQLite3::Exception", message: "disk full", backtrace: "x",
                         source: "DatabaseBackupJob", first_seen_at: 1.hour.ago, last_seen_at: 1.hour.ago)
      get backups_path
      expect(response.body).to include("No backup in the last day.", "disk full", %(href="#{error_events_path}"))
    end
  end

  describe "back up now" do
    it "enqueues the backup job" do
      sign_in_as owner
      expect { post backups_path }.to have_enqueued_job(DatabaseBackupJob)
      expect(response).to redirect_to(backups_path)
      follow_redirect!
      expect(response.body).to include("Backup started. Refresh in a moment to see it.")
    end
  end

  describe "retention" do
    before { sign_in_as owner }

    it "saves a valid number" do
      patch backups_path, params: { household: { backup_retention: "30" } }
      expect(response).to redirect_to(backups_path)
      expect(household.reload.backup_retention).to eq(30)
      expect(AuditEvent.where(auditable_type: "Household", auditable_id: household.id, action: "update", user: owner)).to exist
      follow_redirect!
      expect(response.body).to include("Retention saved.")
    end

    it "re-renders with an error for junk input" do
      [ "", "abc", "0", "366" ].each do |value|
        patch backups_path, params: { household: { backup_retention: value } }
        expect(response).to have_http_status(:unprocessable_content), "expected #{value.inspect} to be rejected"
        expect(response.body).to include("Backup retention")
      end
      expect(household.reload.backup_retention).to eq(14)
    end
  end

  describe "download" do
    before { sign_in_as owner }

    it "sends an existing snapshot" do
      write_snapshot("2026-10-15")
      get backup_download_path("goodbooks-2026-10-15.sqlite3")
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("snapshot 2026-10-15")
      expect(response.headers["Content-Disposition"]).to include("attachment", "goodbooks-2026-10-15.sqlite3")
    end

    it "404s for missing or disallowed names" do
      write_snapshot("2026-10-15")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "production.sqlite3"), "live")
      %w[goodbooks-2026-10-16.sqlite3 production.sqlite3 ..%2Fproduction.sqlite3 goodbooks-2026-10-15.sqlite3.tmp].each do |name|
        get "/backups/#{name}/download"
        expect(response).to have_http_status(:not_found), "expected #{name} to 404"
      end
    end
  end
end
