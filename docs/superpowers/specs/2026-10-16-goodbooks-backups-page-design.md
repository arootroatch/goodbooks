# goodbooks Backups Page — Design Spec

Date: 2026-10-16
Status: Draft for review
Kaneo: GB-14
Parent spec: `2026-10-05-goodbooks-design.md`. Its cross-cutting rules (§3: money, authorization, seeds, testing) apply unchanged.

## 1. Purpose

The nightly `DatabaseBackupJob` runs with no visibility in the app: the owner can't see whether it's working, can't change how many snapshots are kept (a hardcoded `KEEP = 14`), and has to read the README to learn how to get a copy off the server or restore one. The Backups page answers "are my backups working?" at a glance, lets the owner set retention, take a snapshot on demand and download any snapshot, and shows the restore steps for a chosen snapshot.

### Understanding from the owner

- **Where backups go is not an app setting.** Snapshots are written to `storage/backups/` inside the `goodbooks_storage` volume; the host decides where that volume lives via `docker-compose.yml`. The page says where they are but doesn't configure it.
- **Retention is configurable in the app.** It is a household setting, not an env var, so it changes without editing YAML or restarting.
- **No in-app restore.** Restoring replaces the live database and needs the app stopped, so the page shows the commands (with the snapshot's date filled in) rather than offering a button.
- **In scope:** status, retention, back up now, download. **Out of scope:** in-app restore, configuring the backup location or schedule, backing up uploaded files or the Solid Queue/Cache/Cable databases, offsite upload, email or push alerts.

### Success criteria

1. The household owner opens **Settings → Backups** and sees when the last snapshot was taken, how many are kept, and a table of every snapshot with its date, size and a **Download** link.
2. If there are no snapshots, or the newest is more than 26 hours old, the page shows a warning. If an unresolved `ErrorEvent` from `DatabaseBackupJob` exists, the warning links to the Errors page.
3. **Back up now** enqueues `DatabaseBackupJob`; the flash says the backup is running. Running it again the same day replaces that day's snapshot.
4. The owner sets **Snapshots to keep** (1–365, default 14). The next backup run prunes to that number. The change appears in the audit log.
5. **Download** streams the chosen snapshot. Only filenames matching `goodbooks-YYYY-MM-DD.sqlite3` that exist in the backups directory are served; anything else 404s.
6. A **How to restore** section shows the README's restore commands with the date of a snapshot chosen from a dropdown filled in.
7. Editors, viewers and users who aren't household owners get 403 on every Backups route, and don't see the sidebar link.
8. The PR passes every CI check.

## 2. Approach

Status is derived from the files on disk, not stored. The snapshot directory is the source of truth, so the page is always accurate and there is no new table to keep in sync. A small PORO, `BackupSnapshots`, owns the directory: it lists snapshots, finds one by filename (with the name guard), reports the newest, and decides whether backups are overdue. The job and the controller both use it, so the directory path and filename pattern live in one place.

Retention moves from the `KEEP` constant to `households.backup_retention`. `Household` is already `audited`, so retention changes are logged with no extra work.

## 3. Data

Migration: `add_column :households, :backup_retention, :integer, null: false, default: 14`.

`Household` validates `backup_retention` as an integer from 1 to 365.

## 4. Components

### 4.1 `BackupSnapshots` (app/models/backup_snapshots.rb)

```ruby
BackupSnapshots.new(dir = BackupSnapshots.default_dir)  # default_dir: Rails.root.join("storage/backups")
  #all        -> [Snapshot], newest first
  #find(name) -> Snapshot or nil; nil unless name =~ /\Agoodbooks-\d{4}-\d{2}-\d{2}\.sqlite3\z/ and the file exists
  #latest     -> Snapshot or nil
  #overdue?(now: Time.current) -> true if latest is nil or latest.taken_at < now - 26.hours
  #prune(keep) -> deletes all but the newest `keep`
  #path_for(date) -> the path for that day's snapshot

Snapshot = Data.define(:name, :path, :date, :size, :taken_at)  # taken_at = file mtime
```

"Newest" is by date in the filename. `.tmp` files are ignored.

### 4.2 `DatabaseBackupJob`

Unchanged in how it copies. It uses `BackupSnapshots` for the path and pruning, and prunes to `Household.instance.backup_retention` instead of `KEEP`. The `dir:` keyword stays for tests.

### 4.3 `BackupsController`

`before_action :require_household_owner!`. Routes:

```ruby
resource :backups, only: %i[show create update]   # /backups
get "backups/:name/download", to: "backup_downloads#show", as: :backup_download, constraints: { name: /[^\/]+/ }
```

- `show`: snapshots, latest, overdue flag, the open backup `ErrorEvent` if any, and the household for the retention form.
- `create`: `DatabaseBackupJob.perform_later`, then redirect with "Backup started. Refresh in a moment to see it."
- `update`: updates `backup_retention`. Re-renders with errors on an invalid value.
- `BackupDownloadsController#show` (owner-only): `BackupSnapshots.new.find(params[:name])` or 404, then `send_file path, filename: name, type: "application/vnd.sqlite3"`.

Splitting the download into its own controller keeps `BackupsController` RESTful.

### 4.4 View (app/views/backups/show.html.erb)

1. **Status**: "Last backup: <time> · Keeping <n>", or a warning: "No backup in the last day." / "No backups yet." with "See Errors" if a backup error is open. Text says where the snapshots are: `backups/` in the `goodbooks_storage` volume, nightly at 3:00am.
2. **Back up now** button.
3. **Snapshots** table: date, size (`number_to_human_size`), Download. Notes underneath: a snapshot can't sign anyone in without the keys in `docker-compose.yml`, and it holds the database only, not uploaded files. Offsite copies of the whole volume (README) are still needed.
4. **Retention** form: "Snapshots to keep", number field 1–365, with help text saying extras are deleted on the next backup.
5. **How to restore**: a snapshot `<select>` and the restore command block with the date filled in. A small Stimulus controller swaps the date when the selection changes. Without JS, the newest snapshot's date is shown. Includes the note that it stops the app and that anything entered after the snapshot is lost.

Sidebar: add "Backups" to `settings_links` (`app/helpers/navigation_helper.rb`) for household owners, after "Audit log".

### 4.5 Seeds and README

`demo:seed` writes no snapshot files (the dev backups directory is real disk). In development the page just shows "No backups yet" until **Back up now** is clicked. The README's Backups section mentions the page and that retention is set there.

## 5. Error handling

- Job failures already reach `ErrorEvent` through the `Rails.error` subscriber. The page links to them rather than duplicating them.
- A missing backups directory reads as "no snapshots", not an error.
- Download of a name that fails the guard or doesn't exist: 404.

## 6. Testing

- `BackupSnapshots` spec (tmp dir): ordering, ignores `.tmp` and unrelated files, `find` rejects traversal (`../production.sqlite3`, `goodbooks-2026-10-14.sqlite3/../x`) and non-matching names, `overdue?` for none / fresh / 27h old, `prune`.
- `DatabaseBackupJob` spec: prunes to the household's retention.
- `Household` model spec: retention validation.
- Request specs: owner gets 200 on show; editor/viewer get 403 on every route; `create` enqueues the job; `update` saves valid retention and re-renders invalid; download serves an existing snapshot and 404s bad or missing names.
- System spec: owner sees a seeded snapshot, changes retention, picks a snapshot in the restore dropdown and sees its date in the command.
