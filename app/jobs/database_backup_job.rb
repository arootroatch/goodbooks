class DatabaseBackupJob < ApplicationJob
  KEEP = 14

  class BackupError < StandardError; end

  def perform(dir: Rails.root.join("storage/backups").to_s, today: Date.current)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "goodbooks-#{today.iso8601}.sqlite3")
    tmp = "#{path}.tmp"

    copy_to(tmp)
    File.rename(tmp, path)
    prune(dir)
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

  def prune(dir)
    Dir.glob(File.join(dir, "goodbooks-*.sqlite3")).sort.reverse.drop(KEEP).each { File.delete(_1) }
  end
end
