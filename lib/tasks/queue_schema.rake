# A queue DB with schema_migrations but no tables looks initialized, and the dump
# empties db/queue_schema.rb; this loads the schema (#1148, troubleshooting doc).
namespace :db do
  namespace :queue do
    desc "Load db/queue_schema.rb when the queue database is missing Solid Queue's tables"
    task ensure_schema: :environment do
      config = ActiveRecord::Base.configurations
                                 .configs_for(env_name: Rails.env, name: "queue")
      next if config.nil?

      loaded = ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |connection|
        connection.table_exists?("solid_queue_processes")
      end
      next if loaded

      puts "Queue database is missing Solid Queue's tables — loading db/queue_schema.rb"
      Rake::Task["db:schema:load:queue"].invoke
    rescue ActiveRecord::NoDatabaseError
      # Not created yet: db:prepare/db:migrate load the schema next.
      next
    end
  end

  # db:prepare (bin/setup, entrypoint) and db:migrate can both reach this state.
  %w[migrate prepare].each do |entry|
    task entry => "db:queue:ensure_schema"
  end
end
