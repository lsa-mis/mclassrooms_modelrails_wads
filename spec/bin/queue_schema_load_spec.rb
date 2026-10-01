require "rails_helper"
require "tmpdir"

# A real checkout: test has no queue database, and the subject is the committed
# schema file. Loads bin/fork's CLEAN_GIT_ENV rather than a second copy.
load Rails.root.join("bin/fork")

RSpec.describe "db:migrate against a half-initialized queue database" do
  # Builds the half-initialized queue DB directly; a fresh clone is fine (#1148).
  # The clone carries COMMITTED content, so an uncommitted fix reads red here.
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

    FileUtils.ln_s(Rails.root.join("node_modules"), checkout.join("node_modules"), force: true) if
      Rails.root.join("node_modules").exist?

    FileUtils.rm_f(Dir[checkout.join("storage/*.sqlite3*")])
    queue_db = checkout.join("storage/development_queue.sqlite3")
    FileUtils.mkdir_p(queue_db.dirname)
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
