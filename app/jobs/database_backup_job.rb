class DatabaseBackupJob < ApplicationJob
  KEEP = 14

  def perform(dir: Rails.root.join("storage/backups").to_s, today: Date.current)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "goodbooks-#{today.iso8601}.sqlite3")
    FileUtils.rm_f(path)

    destination = SQLite3::Database.new(path)
    backup = SQLite3::Backup.new(destination, "main", ActiveRecord::Base.connection.raw_connection, "main")
    backup.step(-1)
    backup.finish
    destination.close

    Dir.glob(File.join(dir, "goodbooks-*.sqlite3")).sort.reverse.drop(KEEP).each { File.delete(_1) }
  end
end
