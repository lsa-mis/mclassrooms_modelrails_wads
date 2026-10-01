require "rails_helper"

# Fork-readiness guard: a downstream fork (or any fresh checkout) must be able
# to run the full migration history from an empty database and arrive at
# exactly the structure schema.rb describes. Catches migrations that reference
# application models (which evolve past the schema the migration runs under)
# and silent DDL no-ops. Runs in a subprocess so the suite's own database
# connections are never touched.
RSpec.describe "migrating a fresh database from zero", type: :task do
  let(:script) { Rails.root.join("spec/migrations/support/fresh_migrate_probe.rb") }

  def probe(env = {})
    output = IO.popen(env, [ Rails.root.join("bin/rails").to_s, "runner", script.to_s ], err: [ :child, :out ], &:read)
    [ $?.exitstatus, output ]
  end

  it "completes the full migration history and matches schema.rb" do
    status, output = probe

    expect(output).to include("MIGRATE_COMPLETED"), "migrations failed from zero:\n#{output.lines.last(15).join}"
    expect(output).to include("PARITY_OK"), "migrated structure diverges from schema.rb:\n#{output.lines.grep(/^DIFF/).join}"
    expect(status).to eq(0)
  end

  it "exits non-zero and names the repair when schema.rb carries a change no migration makes" do
    drifted = Rails.root.join("tmp/drifted_schema_#{ENV.fetch('TEST_ENV_NUMBER', '')}.rb")
    schema = Rails.root.join("db/schema.rb").read
    index_line = schema.lines.find { |line| line.match?(/^\s+t\.index /) }
    drifted.write(schema.sub(index_line, ""))

    status, output = probe("SCHEMA" => drifted.to_s)

    expect([ status, output ]).to match([ 1, a_string_including("DIFF only-in-migrated", "bin/rails db:schema:regenerate") ])
  ensure
    FileUtils.rm_f(drifted)
  end

  it "runs before every commit that stages db/schema.rb" do
    command = YAML.safe_load(Rails.root.join("lefthook.yml").read).dig("pre-commit", "commands", "schema_parity") || {}

    expect(command).to include("glob" => "db/schema.rb", "run" => a_string_including("spec/migrations/support/fresh_migrate_probe.rb"))
  end
end
