require "rails_helper"

# The template's single-host topology means one SQLite file per test database,
# and config/database.yml installs a 5s Ruby-level busy handler (#304). Two
# processes on the same test DB therefore do not fail fast — every contended
# statement waits out the handler before raising, so a 12-minute suite crawls
# for over an hour and sheds failures scattered across unrelated files, none of
# which name the cause.
#
# Observed in a fork on 2026-08-05: 85 minutes, 30+ phantom failures. Killing it
# made things worse — `pkill -f "bundle exec rspec"` matched the wrapper and
# orphaned the child, which kept the WAL lock, so every later run failed in
# `create(:workspace)`.
RSpec.describe TestDatabaseLockGuard do
  let(:db_path) { "/tmp/probe-test.sqlite3" }

  describe ".database_path" do
    it "names the plain runner's database" do
      expect(described_class.database_path(env_number: nil)).to end_with("storage/test.sqlite3")
    end

    # Workers are safe from each other precisely because the file differs —
    # the guard has to check the file THIS process will open, not a fixed one.
    it "names a parallel worker's own database" do
      expect(described_class.database_path(env_number: "4")).to end_with("storage/test4.sqlite3")
    end

    # The trap the database.yml comment records: TEST_ENV_NUMBER is "" for
    # worker 1, so it shares storage/test.sqlite3 with a plain `bundle exec
    # rspec`. A parallel run and a plain run DO collide.
    it "treats worker 1 as sharing the plain runner's database" do
      expect(described_class.database_path(env_number: "")).to eq(described_class.database_path(env_number: nil))
    end
  end

  describe ".verify!" do
    it "passes when nothing else holds the database" do
      allow(described_class).to receive(:holder_pids).and_return([])

      expect { described_class.verify!(db_path) }.not_to raise_error
    end

    it "raises, naming the process, when another runner holds it" do
      allow(described_class).to receive(:holder_pids).and_return([ 4242 ])
      allow(described_class).to receive(:describe_process).with(4242).and_return("ruby bin/rspec spec/models")

      expect { described_class.verify!(db_path) }
        .to raise_error(described_class::ContendedDatabaseError, /4242/)
    end

    it "names the remedy rather than only the problem" do
      allow(described_class).to receive(:holder_pids).and_return([ 4242 ])
      allow(described_class).to receive(:describe_process).and_return("ruby bin/rspec")

      expect { described_class.verify!(db_path) }
        .to raise_error(described_class::ContendedDatabaseError, /kill/)
    end

    # A missing lsof must not break the suite — the guard is a convenience, and
    # failing closed on a tooling gap would be worse than the hazard.
    it "stays quiet when lsof is unavailable" do
      allow(described_class).to receive(:lsof_available?).and_return(false)
      expect(described_class).not_to receive(:holder_pids)

      expect { described_class.verify!(db_path) }.not_to raise_error
    end

    it "ignores this process's own hold on the file" do
      allow(described_class).to receive(:lsof_available?).and_return(true)
      allow(described_class).to receive(:raw_holder_pids).and_return([ Process.pid ])

      expect { described_class.verify!(db_path) }.not_to raise_error
    end
  end
end
