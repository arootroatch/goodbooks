# Backups Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An owner-only Backups page that shows snapshot status, lets the owner set retention, back up now, download snapshots, and see restore commands for a chosen snapshot.

**Architecture:** A PORO `BackupSnapshots` owns the backups directory (listing, name-guarded lookup, overdue check, pruning) and is shared by `DatabaseBackupJob` and two controllers. Retention moves from a constant to `households.backup_retention`. Status is read from the files on disk; no new table.

**Tech Stack:** Rails 8, SQLite, Solid Queue, Hotwire/Stimulus (importmap), RSpec + FactoryBot + Capybara (Selenium Chrome).

**Spec:** `docs/superpowers/specs/2026-10-16-goodbooks-backups-page-design.md`

## Global Constraints

- Snapshot filename pattern: `goodbooks-YYYY-MM-DD.sqlite3`; regex `/\Agoodbooks-\d{4}-\d{2}-\d{2}\.sqlite3\z/`.
- Overdue threshold: newest snapshot older than 26 hours, or no snapshots.
- Retention: integer 1–365, default 14, column `households.backup_retention`.
- Every Backups route is household-owner only (`require_household_owner!` → 403).
- Backup job errors are `ErrorEvent`s with `source: "DatabaseBackupJob"`.
- Copy: flash after Back up now is exactly `Backup started. Refresh in a moment to see it.`; after saving retention `Retention saved.`
- Run the suite with `bundle exec rspec`; lint with `bin/rubocop`. Commit after each task with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` trailer.

## Review Focus

1. **No household yet** (nightly job runs before first-run setup): the job must still back up, using the default retention, not raise on `Household.first!`. → test in Task 2.
2. **Junk retention input** (`""`, `"abc"`, `0`, `366`): re-renders with an error (422), never a 500. → test in Task 3.
3. **Backups directory doesn't exist yet** (fresh install, dev): page shows "No backups yet." and the overdue warning, not an exception. → test in Task 3.
4. **Back up now twice on the same day**: one file for that date remains, not two. → test in Task 2.
5. **Download URL with the `.sqlite3` extension** is not swallowed as a Rails format, and traversal names 404. → tests in Tasks 1 and 3.

---

## File Structure

- Create `app/models/backup_snapshots.rb` — directory access: list, find (guarded), latest, overdue?, prune, path_for.
- Modify `config/application.rb` and `config/environments/test.rb` — `config.x.backup_dir` (test points at `tmp/backups-test` so specs never touch `storage/`).
- Create `db/migrate/20261016000001_add_backup_retention_to_households.rb`.
- Modify `app/models/household.rb` — validation + `DEFAULT_BACKUP_RETENTION`.
- Modify `app/jobs/database_backup_job.rb` — use `BackupSnapshots` and household retention.
- Create `app/controllers/backups_controller.rb` (show/create/update), `app/controllers/backup_downloads_controller.rb` (show).
- Create `app/views/backups/show.html.erb`.
- Create `app/javascript/controllers/restore_command_controller.js`.
- Modify `config/routes.rb`, `app/helpers/navigation_helper.rb`, `README.md`.
- Tests: `spec/models/backup_snapshots_spec.rb`, `spec/jobs/database_backup_job_spec.rb`, `spec/models/household_spec.rb`, `spec/requests/backups_spec.rb`, `spec/system/backups_spec.rb`.

---

### Task 1: `BackupSnapshots`

**Files:**
- Create: `app/models/backup_snapshots.rb`
- Modify: `config/application.rb`, `config/environments/test.rb`
- Test: `spec/models/backup_snapshots_spec.rb`

**Interfaces:**
- Produces:
  - `BackupSnapshots.default_dir -> Pathname` (from `Rails.configuration.x.backup_dir`)
  - `BackupSnapshots.new(dir = BackupSnapshots.default_dir)`
  - `#dir -> String`, `#all -> [BackupSnapshots::Snapshot]` newest first, `#find(name) -> Snapshot | nil`, `#latest -> Snapshot | nil`, `#overdue?(now: Time.current) -> Boolean`, `#prune(keep) -> void`, `#path_for(date) -> String`
  - `BackupSnapshots::Snapshot = Data.define(:name, :path, :date, :size, :taken_at)`
  - `BackupSnapshots::OVERDUE_AFTER = 26.hours`

- [ ] **Step 1: Configure the directory**

In `config/application.rb`, inside `class Application`, add:

```ruby
    # Nightly SQLite snapshots (DatabaseBackupJob, Backups page).
    config.x.backup_dir = Rails.root.join("storage/backups")
```

In `config/environments/test.rb`, inside the `configure` block, add:

```ruby
  config.x.backup_dir = Rails.root.join("tmp/backups-test")
```

- [ ] **Step 2: Write the failing spec**

`spec/models/backup_snapshots_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe BackupSnapshots do
  let(:dir) { Dir.mktmpdir }
  let(:snapshots) { BackupSnapshots.new(dir) }

  after { FileUtils.remove_entry(dir) }

  def write(name, content = "x", mtime: Time.current)
    path = File.join(dir, name)
    File.write(path, content)
    File.utime(mtime, mtime, path)
    path
  end

  it "defaults to the configured directory" do
    expect(BackupSnapshots.new.dir).to eq(Rails.configuration.x.backup_dir.to_s)
  end

  describe "#all" do
    it "lists snapshots newest first by the date in the name, ignoring temp and other files" do
      write("goodbooks-2026-10-01.sqlite3", "abc")
      write("goodbooks-2026-10-03.sqlite3")
      write("goodbooks-2026-10-02.sqlite3")
      write("goodbooks-2026-10-04.sqlite3.tmp")
      write("notes.txt")

      all = snapshots.all
      expect(all.map(&:name)).to eq(%w[goodbooks-2026-10-03.sqlite3 goodbooks-2026-10-02.sqlite3 goodbooks-2026-10-01.sqlite3])
      expect(all.last).to have_attributes(date: Date.new(2026, 10, 1), size: 3, path: File.join(dir, "goodbooks-2026-10-01.sqlite3"))
    end

    it "is empty when the directory doesn't exist" do
      expect(BackupSnapshots.new(File.join(dir, "missing")).all).to eq([])
    end
  end

  describe "#find" do
    before { write("goodbooks-2026-10-01.sqlite3") }

    it "finds an existing snapshot by name" do
      expect(snapshots.find("goodbooks-2026-10-01.sqlite3").name).to eq("goodbooks-2026-10-01.sqlite3")
    end

    it "returns nil for names that don't match the pattern or don't exist" do
      write("production.sqlite3")
      ["../production.sqlite3", "production.sqlite3", "goodbooks-2026-10-01.sqlite3/../production.sqlite3",
       "goodbooks-2026-10-02.sqlite3", "goodbooks-2026-10-01.sqlite3.tmp", "", nil].each do |name|
        expect(snapshots.find(name)).to be_nil, "expected #{name.inspect} to be rejected"
      end
    end
  end

  describe "#overdue?" do
    let(:now) { Time.zone.local(2026, 10, 16, 12) }

    it "is overdue with no snapshots" do
      expect(snapshots.overdue?(now:)).to be(true)
    end

    it "is not overdue when the newest snapshot is under 26 hours old" do
      write("goodbooks-2026-10-16.sqlite3", mtime: now - 9.hours)
      expect(snapshots.overdue?(now:)).to be(false)
    end

    it "is overdue when the newest snapshot is over 26 hours old" do
      write("goodbooks-2026-10-15.sqlite3", mtime: now - 27.hours)
      expect(snapshots.overdue?(now:)).to be(true)
    end
  end

  it "#latest is the newest snapshot" do
    write("goodbooks-2026-10-01.sqlite3")
    write("goodbooks-2026-10-02.sqlite3")
    expect(snapshots.latest.date).to eq(Date.new(2026, 10, 2))
  end

  it "#prune keeps the newest N" do
    (1..5).each { write("goodbooks-2026-10-0#{_1}.sqlite3") }
    snapshots.prune(2)
    expect(Dir.children(dir).sort).to eq(%w[goodbooks-2026-10-04.sqlite3 goodbooks-2026-10-05.sqlite3])
  end

  it "#path_for builds the day's path" do
    expect(snapshots.path_for(Date.new(2026, 10, 5))).to eq(File.join(dir, "goodbooks-2026-10-05.sqlite3"))
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bundle exec rspec spec/models/backup_snapshots_spec.rb`
Expected: FAIL with `uninitialized constant BackupSnapshots`.

- [ ] **Step 4: Implement**

`app/models/backup_snapshots.rb`:

```ruby
# The nightly SQLite snapshots in the backups directory. Status on the Backups page is read from these files.
class BackupSnapshots
  NAME = /\Agoodbooks-(\d{4}-\d{2}-\d{2})\.sqlite3\z/
  OVERDUE_AFTER = 26.hours

  Snapshot = Data.define(:name, :path, :date, :size, :taken_at)

  def self.default_dir = Rails.configuration.x.backup_dir

  attr_reader :dir

  def initialize(dir = self.class.default_dir)
    @dir = dir.to_s
  end

  def all
    return [] unless Dir.exist?(dir)

    Dir.children(dir).filter_map { snapshot(_1) }.sort_by(&:date).reverse
  end

  def find(name)
    snapshot(name.to_s)
  end

  def latest = all.first

  def overdue?(now: Time.current)
    newest = latest
    newest.nil? || newest.taken_at < now - OVERDUE_AFTER
  end

  def prune(keep)
    all.drop(keep).each { File.delete(_1.path) }
  end

  def path_for(date) = File.join(dir, "goodbooks-#{date.iso8601}.sqlite3")

  private

  def snapshot(name)
    match = NAME.match(name) or return
    path = File.join(dir, name)
    return unless File.file?(path)

    stat = File.stat(path)
    Snapshot.new(name:, path:, date: Date.iso8601(match[1]), size: stat.size, taken_at: stat.mtime)
  end
end
```

- [ ] **Step 5: Run it to verify it passes**

Run: `bundle exec rspec spec/models/backup_snapshots_spec.rb`
Expected: all examples pass.

- [ ] **Step 6: Commit**

```bash
git add app/models/backup_snapshots.rb spec/models/backup_snapshots_spec.rb config/application.rb config/environments/test.rb
git commit -m "BackupSnapshots: list, find, overdue check and pruning for the backups directory

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Retention setting, and the job uses it

**Files:**
- Create: `db/migrate/20261016000001_add_backup_retention_to_households.rb`
- Modify: `app/models/household.rb`, `app/jobs/database_backup_job.rb`
- Test: `spec/models/household_spec.rb`, `spec/jobs/database_backup_job_spec.rb`

**Interfaces:**
- Consumes: `BackupSnapshots.new(dir)`, `#path_for(date)`, `#prune(keep)` (Task 1).
- Produces: `households.backup_retention` (integer, default 14); `Household::DEFAULT_BACKUP_RETENTION = 14`; `DatabaseBackupJob#perform(dir: BackupSnapshots.default_dir.to_s, today: Date.current)`.

- [ ] **Step 1: Migration**

`db/migrate/20261016000001_add_backup_retention_to_households.rb`:

```ruby
class AddBackupRetentionToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :backup_retention, :integer, null: false, default: 14
  end
end
```

Check the migration version bracket matches the other files in `db/migrate` (use whatever `[8.x]` they use). Run `bin/rails db:migrate` and confirm `db/schema.rb` gains the column.

- [ ] **Step 2: Write failing specs**

Add to `spec/models/household_spec.rb` (create the file with `require "rails_helper"` / `RSpec.describe Household do … end` if it doesn't exist):

```ruby
  describe "backup_retention" do
    it "defaults to 14" do
      expect(create(:household).backup_retention).to eq(14)
    end

    it "must be a whole number from 1 to 365" do
      household = build(:household)
      [0, 366, 2.5, nil, "abc"].each do |value|
        household.backup_retention = value
        expect(household).not_to be_valid, "expected #{value.inspect} to be invalid"
      end
      [1, 365].each do |value|
        household.backup_retention = value
        expect(household).to be_valid
      end
    end
  end
```

In `spec/jobs/database_backup_job_spec.rb`, replace the example `"keeps the newest 14 backups"` with:

```ruby
  it "keeps the newest 14 backups when there's no household yet" do
    16.times { |i| FileUtils.touch(File.join(dir, "goodbooks-2026-09-#{format("%02d", i + 1)}.sqlite3")) }
    DatabaseBackupJob.perform_now(dir: dir, today: Date.new(2026, 10, 5))
    files = Dir.children(dir).sort
    expect(files.size).to eq(14)
    expect(files.last).to eq("goodbooks-2026-10-05.sqlite3")
    expect(files.first).to eq("goodbooks-2026-09-04.sqlite3")
  end

  it "keeps as many backups as the household's retention" do
    create(:household, backup_retention: 3)
    5.times { |i| FileUtils.touch(File.join(dir, "goodbooks-2026-09-0#{i + 1}.sqlite3")) }
    DatabaseBackupJob.perform_now(dir: dir, today: Date.new(2026, 10, 5))
    expect(Dir.children(dir).sort).to eq(%w[goodbooks-2026-09-04.sqlite3 goodbooks-2026-09-05.sqlite3 goodbooks-2026-10-05.sqlite3])
  end

  it "replaces the day's snapshot when run twice the same day" do
    2.times { DatabaseBackupJob.perform_now(dir: dir, today: Date.new(2026, 10, 5)) }
    expect(Dir.children(dir)).to eq(%w[goodbooks-2026-10-05.sqlite3])
  end

  it "writes to the configured backups directory by default" do
    allow(BackupSnapshots).to receive(:default_dir).and_return(Pathname(dir))
    DatabaseBackupJob.perform_now(today: Date.new(2026, 10, 5))
    expect(Dir.children(dir)).to eq(%w[goodbooks-2026-10-05.sqlite3])
  end
```

- [ ] **Step 3: Run them to verify they fail**

Run: `bundle exec rspec spec/models/household_spec.rb spec/jobs/database_backup_job_spec.rb`
Expected: the validation example and "keeps as many backups as the household's retention" fail (no validation; job still keeps 14).

- [ ] **Step 4: Implement**

`app/models/household.rb` — add below `DEFAULT_IRS_PAYMENT_URL`:

```ruby
  DEFAULT_BACKUP_RETENTION = 14
```

and below the `irs_payment_url` validation:

```ruby
  validates :backup_retention, numericality: { only_integer: true, in: 1..365 }
```

`app/jobs/database_backup_job.rb` — replace the class body above `private` and the `prune` method:

```ruby
class DatabaseBackupJob < ApplicationJob
  class BackupError < StandardError; end

  def perform(dir: BackupSnapshots.default_dir.to_s, today: Date.current)
    snapshots = BackupSnapshots.new(dir)
    FileUtils.mkdir_p(dir)
    path = snapshots.path_for(today)
    tmp = "#{path}.tmp"

    copy_to(tmp)
    File.rename(tmp, path)
    snapshots.prune(Household.first&.backup_retention || Household::DEFAULT_BACKUP_RETENTION)
  rescue StandardError
    FileUtils.rm_f(tmp) if tmp
    raise
  end

  private

  # copy_to unchanged
```

Delete the old `KEEP` constant and the old private `prune` method. Keep `copy_to` exactly as it is.

- [ ] **Step 5: Run them to verify they pass**

Run: `bundle exec rspec spec/models/household_spec.rb spec/jobs/database_backup_job_spec.rb`
Expected: all pass (including the existing failure-path examples).

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb app/models/household.rb app/jobs/database_backup_job.rb spec/models/household_spec.rb spec/jobs/database_backup_job_spec.rb
git commit -m "Backup retention is a household setting (default 14) instead of a constant

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Backups page — status, snapshots, back up now, download, retention

**Files:**
- Create: `app/controllers/backups_controller.rb`, `app/controllers/backup_downloads_controller.rb`, `app/views/backups/show.html.erb`
- Modify: `config/routes.rb`, `app/helpers/navigation_helper.rb`
- Test: `spec/requests/backups_spec.rb`

**Interfaces:**
- Consumes: `BackupSnapshots` (Task 1), `Household#backup_retention` (Task 2), `DatabaseBackupJob`, `ErrorEvent.unresolved`.
- Produces: routes `backups_path` (GET show, POST create, PATCH update) and `backup_download_path(name)`; view ivars `@snapshots` (Array of Snapshot), `@latest`, `@overdue`, `@backup_error`, `@household`. Task 4 adds a section to `app/views/backups/show.html.erb` using `@snapshots` and `@latest`.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/backups_spec.rb`:

```ruby
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
    File.utime(mtime, mtime, path)
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
      follow_redirect!
      expect(response.body).to include("Retention saved.")
    end

    it "re-renders with an error for junk input" do
      ["", "abc", "0", "366"].each do |value|
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/backups_spec.rb`
Expected: FAIL with `undefined local variable or method 'backups_path'`.

- [ ] **Step 3: Routes**

In `config/routes.rb`, after the `error_events` block:

```ruby
  resource :backups, only: %i[show create update]
  get "backups/:name/download", to: "backup_downloads#show", as: :backup_download, constraints: { name: %r{[^/]+} }, format: false
```

(`format: false` stops Rails reading `.sqlite3` as a format.)

- [ ] **Step 4: Controllers**

`app/controllers/backups_controller.rb`:

```ruby
class BackupsController < ApplicationController
  before_action :require_household_owner!
  before_action :load_page

  def show
  end

  def create
    DatabaseBackupJob.perform_later
    redirect_to backups_path, notice: "Backup started. Refresh in a moment to see it.", status: :see_other
  end

  def update
    if @household.update(params.expect(household: [:backup_retention]))
      redirect_to backups_path, notice: "Retention saved.", status: :see_other
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def load_page
    snapshots = BackupSnapshots.new
    @snapshots = snapshots.all
    @latest = @snapshots.first
    @overdue = snapshots.overdue?
    @backup_error = ErrorEvent.unresolved.recent_first.find_by(source: DatabaseBackupJob.name)
    @household = Household.instance
  end
end
```

`app/controllers/backup_downloads_controller.rb`:

```ruby
class BackupDownloadsController < ApplicationController
  before_action :require_household_owner!

  def show
    snapshot = BackupSnapshots.new.find(params[:name]) or return head(:not_found)
    send_file snapshot.path, filename: snapshot.name, type: "application/vnd.sqlite3", disposition: :attachment
  end
end
```

- [ ] **Step 5: View**

`app/views/backups/show.html.erb`:

```erb
<header class="page-header">
  <h1>Backups</h1>
  <div class="button-group no-print">
    <%= button_to "Back up now", backups_path, class: "button primary" %>
  </div>
</header>

<% if @latest.nil? || @overdue %>
  <p class="flash-alert">
    <%= @latest.nil? ? "No backups yet." : "No backup in the last day." %>
    <% if @backup_error %>
      The last backup failed: <%= @backup_error.message %>. <%= link_to "See Errors", error_events_path %>
    <% end %>
  </p>
<% end %>

<% if @latest %>
  <p>Last backup: <strong><%= l(@latest.taken_at, format: :long) %></strong> · Keeping <%= @household.backup_retention_in_database %></p>
<% end %>
<p class="muted">
  Every night at 3:00am the app copies the database to <code>backups/</code> in the <code>goodbooks_storage</code> Docker volume.
</p>

<h2>Snapshots</h2>
<% if @snapshots.empty? %>
  <p>No snapshots yet.</p>
<% else %>
  <table>
    <thead><tr><th>Date</th><th class="num">Size</th><th></th></tr></thead>
    <tbody>
      <% @snapshots.each do |snapshot| %>
        <tr>
          <td><%= snapshot.date.iso8601 %></td>
          <td class="num"><%= number_to_human_size(snapshot.size) %></td>
          <td><%= link_to "Download", backup_download_path(snapshot.name), data: { turbo: false } %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>
<p class="muted">
  A snapshot can't sign anyone in without the keys in your <code>docker-compose.yml</code>, so keep a copy of that file too.
  Snapshots hold the database only, not uploaded files, so still copy the whole volume offsite (see the README).
</p>

<h2>Retention</h2>
<%= form_with model: @household, url: backups_path, method: :patch do |f| %>
  <%= render "shared/errors", record: @household %>
  <p>
    <%= f.label :backup_retention, "Snapshots to keep" %>
    <%= f.number_field :backup_retention, min: 1, max: 365, step: 1, required: true %>
    <small class="muted">Older snapshots beyond this number are deleted at the next backup.</small>
  </p>
  <%= f.submit "Save" %>
<% end %>
```

`backup_retention_in_database` shows the saved value even when a re-render carries an invalid one. Check `app/views/shared/_errors.html.erb` renders full messages (so "Backup retention must be…" appears); if it doesn't, the spec's `"Backup retention"` assertion will tell you.

- [ ] **Step 6: Sidebar link**

In `app/helpers/navigation_helper.rb` `settings_links`, directly after the `"Audit log"` line add:

```ruby
      (nav_link "Backups", backups_path if user.household_owner?),
```

- [ ] **Step 7: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/backups_spec.rb`
Expected: all pass. Then run `bundle exec rspec spec/requests spec/helpers` to catch sidebar/navigation specs that enumerate settings links; update any such expectation to include "Backups" for owners.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/backups_controller.rb app/controllers/backup_downloads_controller.rb app/views/backups app/helpers/navigation_helper.rb spec/requests/backups_spec.rb
git commit -m "Backups page: status, snapshots with downloads, back up now, retention

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: How to restore, system spec, README

**Files:**
- Create: `app/javascript/controllers/restore_command_controller.js`, `spec/system/backups_spec.rb`
- Modify: `app/views/backups/show.html.erb`, `README.md`

**Interfaces:**
- Consumes: `@snapshots`, `@latest` from `BackupsController#show` (Task 3).
- Produces: Stimulus controller `restore-command` with targets `select` and `date`, action `restore-command#update`.

Stimulus controllers in `app/javascript/controllers/` are auto-registered (check `index.js` uses `eagerLoadControllersFrom` / `lazyLoadControllersFrom`; if it lists controllers by hand, add this one the same way).

- [ ] **Step 1: Write the failing system spec**

`spec/system/backups_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/system/backups_spec.rb`
Expected: FAIL — `Unable to find css "pre.restore-command"`.

- [ ] **Step 3: Stimulus controller**

`app/javascript/controllers/restore_command_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Fills the chosen snapshot's date into the restore command on the Backups page.
export default class extends Controller {
  static targets = ["select", "date"]

  update() {
    this.dateTargets.forEach((el) => { el.textContent = this.selectTarget.value })
  }
}
```

- [ ] **Step 4: Restore section**

Append to `app/views/backups/show.html.erb`:

```erb
<% if @latest %>
  <h2>How to restore</h2>
  <div data-controller="restore-command">
    <p>
      <label for="restore_snapshot">Snapshot to restore</label>
      <select id="restore_snapshot" data-restore-command-target="select" data-action="restore-command#update">
        <%= options_for_select(@snapshots.map { _1.date.iso8601 }, @latest.date.iso8601) %>
      </select>
    </p>
    <p>On the server, in the folder with your <code>docker-compose.yml</code>, run:</p>
<pre class="restore-command">docker compose stop app
docker run --rm -v goodbooks_storage:/data alpine sh -c '
  cp /data/backups/goodbooks-<span data-restore-command-target="date"><%= @latest.date.iso8601 %></span>.sqlite3 /data/production.sqlite3 &&
  rm -f /data/production.sqlite3-wal /data/production.sqlite3-shm &&
  chown 1000:1000 /data/production.sqlite3'
docker compose start app</pre>
    <p class="muted">
      This stops goodbooks while it runs, which is why it isn't a button. Anything entered after the snapshot is lost,
      and bank transactions sync again on the next run.
    </p>
  </div>
<% end %>
```

Keep the `<pre>` unindented so the command copies cleanly.

- [ ] **Step 5: Run the system spec to verify it passes**

Run: `bundle exec rspec spec/system/backups_spec.rb`
Expected: PASS.

- [ ] **Step 6: README**

In `README.md` under `## Backups`, replace the **Nightly snapshots.** paragraph with:

```markdown
**Nightly snapshots.** Every night the app writes a consistent copy of the main database to
`backups/goodbooks-YYYY-MM-DD.sqlite3` in the volume and keeps the latest 14. The household owner's **Backups** page
shows when the last one ran, warns if one is missed, takes one on demand, downloads any of them, and sets how many to
keep. That protects against mistakes, not against losing the server's disk.
```

and add after the restore command block:

```markdown
The **Backups** page shows the same command with a chosen snapshot's date filled in.
```

- [ ] **Step 7: Full verification**

Run: `bundle exec rspec` — expected `0 failures`.
Run: `bin/rubocop` — expected no offenses.
Run: `bin/brakeman -q --no-pager` — expected no new warnings (the `send_file` path comes from `BackupSnapshots#find`, which only returns guarded names; if Brakeman flags it anyway, confirm the guard and add an ignore entry with that note).

- [ ] **Step 8: Commit**

```bash
git add app/javascript/controllers/restore_command_controller.js app/views/backups/show.html.erb spec/system/backups_spec.rb README.md
git commit -m "Backups page: restore command for a chosen snapshot; README points to the page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
