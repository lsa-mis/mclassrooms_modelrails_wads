require "rails_helper"

# Fork-readiness guard: a downstream fork (or any fresh checkout) must be able
# to run the full migration history from an empty database and arrive at
# exactly the structure schema.rb describes. Catches migrations that reference
# application models (which evolve past the schema the migration runs under)
# and silent DDL no-ops. Runs in a subprocess so the suite's own database
# connections are never touched.
RSpec.describe "migrating a fresh database from zero", type: :task do
  it "completes the full migration history and matches schema.rb" do
    probe = Rails.root.join("tmp/fresh_migrate_probe.sqlite3")
    reference = Rails.root.join("tmp/fresh_schema_probe.sqlite3")
    script = Rails.root.join("spec/migrations/support/fresh_migrate_probe.rb")
    [ probe, reference ].each { |p| FileUtils.rm_f(p) }

    output = `#{Rails.root.join("bin/rails")} runner #{script} 2>&1`

    expect(output).to include("MIGRATE_COMPLETED"), "migrations failed from zero:\n#{output.lines.last(15).join}"
    expect(output).to include("PARITY_OK"), "migrated structure diverges from schema.rb:\n#{output.lines.grep(/^DIFF/).join}"
  ensure
    [ probe, reference ].each { |p| FileUtils.rm_f(p) }
  end
end
