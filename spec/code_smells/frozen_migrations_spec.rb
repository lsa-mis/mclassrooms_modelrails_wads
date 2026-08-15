require "rails_helper"

# Migrations replay from zero on every fresh clone — a fork's very first
# command. A migration that touches a live app class breaks the moment a fork
# renames the model or reshapes the constant it references (two shipped
# instances froze under #449: Project/ProjectTools::Registry and User).
# Data work inside a migration uses an inline `class X < ActiveRecord::Base`
# with a literal table name and literal values: the migration's world as of
# its timestamp, deliberately not tracking the app.
#
# The runtime complement is spec/migrations/fresh_database_migration_spec.rb,
# which actually replays the history; this static guard fails at the moment
# the reference is WRITTEN instead of on the next fresh clone.
RSpec.describe "Code smell: migrations reference no live app classes" do
  # Receivers doing data work in a migration body.
  data_call = /^\s*([A-Z]\w*(?:::\w+)*)\.(?:update_all|delete_all|destroy_all|create!?|find_each|find_by|where|reset_column_information|upsert(?:_all)?)\b/

  it "data work in db/migrate uses inline models, not app constants" do
    offenders = Dir[Rails.root.join("db/migrate/*.rb")].flat_map do |file|
      source = File.read(file)
      inline_models = source.scan(/class\s+(\w+)\s*<\s*ActiveRecord::Base/).flatten

      source.lines.each_with_index.filter_map do |line, i|
        next unless (match = line.match(data_call))

        receiver = match[1]
        next if inline_models.include?(receiver)
        next if receiver.start_with?("ActiveRecord")

        "#{Pathname(file).relative_path_from(Rails.root)}:#{i + 1}: #{line.strip}"
      end
    end

    expect(offenders).to be_empty,
      "Migrations must not reference live app classes — a fork that renames " \
      "the model breaks db:migrate from zero (#449). Define an inline model " \
      "(class MigrationFoo < ActiveRecord::Base; self.table_name = \"foos\") " \
      "and use literal values:\n  #{offenders.join("\n  ")}"
  end
end
