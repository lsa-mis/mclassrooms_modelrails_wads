# The queue database is schema-load-only: `db/queue_migrate` is deliberately
# empty, because Solid Queue's tables come from `db/queue_schema.rb` rather than
# from migrations we own.
#
# Rails decides a database is already initialized by asking whether
# `schema_migrations` exists (DatabaseTasks#initialize_database). A queue
# database that has that table and nothing else therefore looks initialized,
# skips the schema load, has no migrations to run — and the post-migrate dump
# then writes the empty result over the committed 141-line schema file. The
# developer sees `db/queue_schema.rb` modified for no reason, `bin/jobs` crashes
# `bin/dev` at boot, and neither symptom names its cause.
#
# A half-initialized queue database is reachable in ordinary use: `bin/jobs`
# auto-creates the file, and a preserved workspace (a devcontainer Rebuild rather
# than a delete-and-recreate) keeps it. This check asks the question Rails' own
# check cannot — is the table Solid Queue actually needs present? — and loads the
# schema when it is not. It ran only inside `.devcontainer/setup.sh` before, so
# everyone outside a devcontainer was unprotected (#1148).
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
      # Nothing to repair yet: db:prepare/db:migrate create it and load the
      # schema on the ordinary path a moment from now.
      next
    end
  end

  # Both entry points, because either can reach a half-initialized queue database:
  # db:prepare is what bin/setup and the docker entrypoint run, and db:migrate is
  # what an editor's "run pending migrations" affordance runs.
  %w[migrate prepare].each do |entry|
    task entry => "db:queue:ensure_schema"
  end
end
