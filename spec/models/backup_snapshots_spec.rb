require "rails_helper"

RSpec.describe BackupSnapshots do
  let(:dir) { Dir.mktmpdir }
  let(:snapshots) { BackupSnapshots.new(dir) }

  after { FileUtils.remove_entry(dir) }

  def write(name, content = "x", mtime: Time.current)
    path = File.join(dir, name)
    File.write(path, content)
    File.utime(mtime.to_time, mtime.to_time, path)
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
      [ "../production.sqlite3", "production.sqlite3", "goodbooks-2026-10-01.sqlite3/../production.sqlite3",
       "goodbooks-2026-10-02.sqlite3", "goodbooks-2026-10-01.sqlite3.tmp", "", nil ].each do |name|
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
