# db:migrate dumps schema.rb from the development database, which also carries other
# branches' migrations; this dumps from a scratch database built by db/migrate alone.
namespace :db do
  namespace :schema do
    desc "Rewrite db/schema.rb from db/migrate alone, never from the development database"
    task regenerate: :environment do
      Dir.mktmpdir("schema-regenerate") do |dir|
        config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
          Rails.env, "primary", adapter: "sqlite3", database: File.join(dir, "scratch.sqlite3")
        )
        ActiveRecord::Migration.verbose = false
        ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |connection|
          connection.pool.migration_context.migrate
        end
        ActiveRecord::Tasks::DatabaseTasks.dump_schema(config)
        puts "#{ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(config)} regenerated from db/migrate"
      end
    end
  end
end
