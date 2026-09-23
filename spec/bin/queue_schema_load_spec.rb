require "rails_helper"
require "tmpdir"

# Spawns a real checkout, because this cannot be reproduced in process: the test
# environment has no `queue` database configured at all, and the behaviour under
# test is what `db:migrate` does to the development queue database and to the
# committed schema file on disk.
#
# `load`ing bin/fork for ForkFlow::CLEAN_GIT_ENV rather than defining a second
# copy — the same reason spec/bin/fork_spec.rb gives: a constant defined in a
# describe block lands on Object and collides across parallel workers.
load Rails.root.join("bin/fork")

RSpec.describe "db:migrate against a half-initialized queue database" do
  # Rails asks `schema_migrations.table_exists?` to decide a database is already
  # initialized (DatabaseTasks#initialize_database). A queue database carrying
  # that table and nothing else answers yes, so the schema load is skipped, the
  # empty db/queue_migrate runs nothing, and the post-migrate dump writes the
  # empty result over the committed schema.
  #
  # Reachable in ordinary use: bin/jobs auto-creates the queue file, and a
  # preserved workspace (a devcontainer Rebuild rather than a delete-and-recreate)
  # keeps it. A genuinely empty storage/ directory is NOT affected — Rails loads
  # the schema correctly there, which is why this spec builds the specific state
  # rather than simply cloning and migrating (#1148).
  # NOTE: the clone carries COMMITTED content only, so this exercises HEAD rather
  # than the working tree. A fix that is written but not yet committed reads as a
  # failure here, which is the correct answer to "would a fresh clone survive
  # this?" and worth knowing before debugging a red run.
  let(:workdir) { Pathname.new(Dir.mktmpdir) }
  let(:checkout) { workdir.join("fresh") }

  after { FileUtils.rm_rf(workdir) }

  def run(*command, env: {})
    system(ForkFlow::CLEAN_GIT_ENV.merge(env), *command,
           chdir: checkout.to_s, out: File::NULL, err: File::NULL)
  end

  before do
    system(ForkFlow::CLEAN_GIT_ENV, "git", "clone", "--quiet", "--local", "--no-hardlinks",
           Rails.root.to_s, checkout.to_s, out: File::NULL, err: File::NULL) ||
      raise("could not clone the checkout under test")

    # Bundler and node_modules come from the real checkout; only the tree and
    # its databases need to be separate.
    FileUtils.ln_s(Rails.root.join("node_modules"), checkout.join("node_modules"), force: true) if
      Rails.root.join("node_modules").exist?

    FileUtils.rm_f(Dir[checkout.join("storage/*.sqlite3*")])
    queue_db = checkout.join("storage/development_queue.sqlite3")
    FileUtils.mkdir_p(queue_db.dirname)
    # The half-initialized state, built directly: the table Rails looks for,
    # without the tables Solid Queue needs.
    system("sqlite3", queue_db.to_s,
           "CREATE TABLE schema_migrations (version varchar NOT NULL PRIMARY KEY);",
           out: File::NULL, err: File::NULL) || raise("could not seed the queue database")
  end

  it "loads the queue schema instead of dumping an empty database over it" do
    committed = checkout.join("db/queue_schema.rb").read

    expect(run("bin/rails", "db:migrate", env: { "RAILS_ENV" => "development" }))
      .to be(true), "db:migrate failed outright"

    expect(checkout.join("db/queue_schema.rb").read).to eq(committed),
      "db:migrate rewrote db/queue_schema.rb — the queue database was treated as " \
      "initialized, migrated nothing, and the post-migrate dump overwrote the " \
      "committed schema with an empty one"

    tables = `sqlite3 #{checkout.join('storage/development_queue.sqlite3')} ".tables"`
    expect(tables).to include("solid_queue_processes"),
      "the queue database still has no Solid Queue tables, so bin/jobs will crash bin/dev at boot"
  end
end
