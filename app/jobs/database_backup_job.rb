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

  def copy_to(tmp)
    FileUtils.rm_f(tmp)
    destination = backup = nil
    destination = SQLite3::Database.new(tmp)
    backup = SQLite3::Backup.new(destination, "main", ActiveRecord::Base.connection.raw_connection, "main")
    result = backup.step(-1)
    raise BackupError, "backup incomplete (step returned #{result.inspect})" unless result == SQLite3::Constants::ErrorCode::DONE
  ensure
    backup&.finish
    destination&.close
  end
end
