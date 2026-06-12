# Runs the full migration history into a scratch SQLite database, loads
# schema.rb into a second one, and structurally compares the two. Executed via
# `bin/rails runner` from fresh_database_migration_spec.rb so connection
# swapping cannot leak into the test suite.

def structure_snapshot
  conn = ActiveRecord::Base.connection
  tables = conn.tables.sort - [ "ar_internal_metadata", "schema_migrations" ]
  columns = tables.flat_map do |t|
    conn.columns(t).map { |c| [ t, c.name, c.sql_type.downcase, c.null ] }
  end
  indexes = tables.flat_map do |t|
    conn.indexes(t).map { |i| [ t, i.name, i.columns, i.unique ] }
  end
  { columns: columns.sort, indexes: indexes.sort_by(&:to_s) }
end

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3", database: "tmp/fresh_migrate_probe.sqlite3"
)
begin
  ActiveRecord::MigrationContext.new("db/migrate").migrate
  puts "MIGRATE_COMPLETED"
rescue => e
  puts "MIGRATE_FAILED: #{e.cause ? e.cause.message : e.message}"
  exit
end
migrated = structure_snapshot

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3", database: "tmp/fresh_schema_probe.sqlite3"
)
verbose_was = ActiveRecord::Migration.verbose
ActiveRecord::Migration.verbose = false
load Rails.root.join("db/schema.rb")
ActiveRecord::Migration.verbose = verbose_was
reference = structure_snapshot

if migrated == reference
  puts "PARITY_OK"
else
  %i[columns indexes].each do |kind|
    (migrated[kind] - reference[kind]).each { |d| puts "DIFF only-in-migrated #{kind}: #{d.inspect}" }
    (reference[kind] - migrated[kind]).each { |d| puts "DIFF only-in-schema #{kind}: #{d.inspect}" }
  end
end
