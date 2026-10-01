# Migrates db/migrate into one scratch database, loads schema.rb into another, and compares
# the structures. Run by bin/rails runner from the parity spec and from Lefthook pre-commit.

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

migrated_db = "tmp/fresh_migrate_probe#{ENV['TEST_ENV_NUMBER']}.sqlite3"
schema_db = "tmp/fresh_schema_probe#{ENV['TEST_ENV_NUMBER']}.sqlite3"
FileUtils.rm_f([ migrated_db, schema_db ])
ActiveRecord::Migration.verbose = false

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: migrated_db)
begin
  ActiveRecord::MigrationContext.new("db/migrate").migrate
  puts "MIGRATE_COMPLETED"
rescue => e
  puts "MIGRATE_FAILED: #{e.cause ? e.cause.message : e.message}"
  exit 1
end
migrated = structure_snapshot

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: schema_db)
load ENV.fetch("SCHEMA", Rails.root.join("db/schema.rb").to_s)
reference = structure_snapshot
FileUtils.rm_f([ migrated_db, schema_db ])

if migrated == reference
  puts "PARITY_OK"
else
  %i[columns indexes].each do |kind|
    (migrated[kind] - reference[kind]).each { |d| puts "DIFF only-in-migrated #{kind}: #{d.inspect}" }
    (reference[kind] - migrated[kind]).each { |d| puts "DIFF only-in-schema #{kind}: #{d.inspect}" }
  end
  puts "db/schema.rb does not match a fresh migrate of db/migrate — run bin/rails db:schema:regenerate"
  exit 1
end
