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
