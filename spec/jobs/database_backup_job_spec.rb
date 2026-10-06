require "rails_helper"

RSpec.describe DatabaseBackupJob do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  it "writes a readable copy of the database" do
    DatabaseBackupJob.perform_now(dir: dir, today: Date.new(2026, 10, 5))
    path = File.join(dir, "goodbooks-2026-10-05.sqlite3")
    db = SQLite3::Database.new(path)
    tables = db.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
    db.close
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

  context "when the copy fails" do
    let(:today) { Date.new(2026, 10, 5) }
    let(:existing) { %w[2026-09-01 2026-09-02].map { |d| "goodbooks-#{d}.sqlite3" } }

    before do
      existing.each { |f| File.write(File.join(dir, f), "old") }
      failing = instance_double(SQLite3::Backup, finish: nil)
      allow(failing).to receive(:step).and_raise(SQLite3::Exception, "disk full")
      allow(SQLite3::Backup).to receive(:new).and_return(failing)
    end

    it "raises and leaves no partial or temporary file" do
      expect { DatabaseBackupJob.perform_now(dir: dir, today: today) }.to raise_error(SQLite3::Exception, "disk full")
      expect(Dir.children(dir).sort).to eq(existing)
    end

    it "does not prune existing backups" do
      12.times { |i| File.write(File.join(dir, "goodbooks-2026-08-#{format("%02d", i + 1)}.sqlite3"), "old") }
      expect { DatabaseBackupJob.perform_now(dir: dir, today: today) }.to raise_error(SQLite3::Exception)
      expect(Dir.children(dir).size).to eq(14)
    end
  end
end
