require "rails_helper"

RSpec.describe DatabaseBackupJob do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  it "writes a readable copy of the database" do
    DatabaseBackupJob.perform_now(dir: dir, today: Date.new(2026, 10, 5))
    path = File.join(dir, "goodbooks-2026-10-05.sqlite3")
    tables = SQLite3::Database.new(path).execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
    expect(tables).to include("households", "transactions")
  end

  it "keeps the newest 14 backups" do
    16.times { |i| FileUtils.touch(File.join(dir, "goodbooks-2026-09-#{format("%02d", i + 1)}.sqlite3")) }
    DatabaseBackupJob.perform_now(dir: dir, today: Date.new(2026, 10, 5))
    files = Dir.children(dir).sort
    expect(files.size).to eq(14)
    expect(files.last).to eq("goodbooks-2026-10-05.sqlite3")
    expect(files.first).to eq("goodbooks-2026-09-04.sqlite3")
  end
end
