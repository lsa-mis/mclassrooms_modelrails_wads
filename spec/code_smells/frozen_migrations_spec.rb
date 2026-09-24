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
#
# It walks the RECEIVER CHAIN rather than matching a constant glued to a data
# call: `UserPreferences.unscoped.update_all` evaded this fence for four
# months, and was cited in a spec review as the house pattern — the opposite
# of what it is (#942).
RSpec.describe "Code smell: migrations reference no live app classes" do
  # A `let`, not a constant: a bare constant in a describe block lands on
  # Object and collides across parallel workers.
  let(:data_calls) do
    %w[
      update_all delete_all destroy_all create create! find_each find_by where
      reset_column_information upsert upsert_all in_batches
    ]
  end

  # The first data call reached from a leading constant, or nil. Balanced
  # (), [] and {} are skipped whole, so an argument list cannot hide the next
  # hop — `where.not(primary_color: [ nil, "" ]).find_each` is one chain.
  def chained_data_call(line)
    return nil unless (match = line.match(/^\s*([A-Z]\w*(?:::\w+)*)/))

    index = match.end(0)
    loop do
      return nil unless line[index] == "."
      return nil unless (segment = line[(index + 1)..].to_s[/\A\w+[!?]?/])
      return segment if data_calls.include?(segment)

      index += 1 + segment.length
      next unless "([{".include?(line[index].to_s)
      return nil unless (index = skip_balanced(line, index))
    end
  end

  def skip_balanced(line, open_index)
    opener = line[open_index]
    closer = { "(" => ")", "[" => "]", "{" => "}" }.fetch(opener)
    depth = 0
    line[open_index..].each_char.with_index do |char, offset|
      depth += 1 if char == opener
      depth -= 1 if char == closer
      return open_index + offset + 1 if depth.zero?
    end
    nil
  end

  # Takes SOURCE so the controls below can feed it planted text.
  def offenders_in(source, path: "db/migrate/probe.rb")
    inline_models = source.scan(/class\s+(\w+)\s*<\s*ActiveRecord::Base/).flatten

    source.lines.each_with_index.filter_map do |line, i|
      next unless (call = chained_data_call(line))

      receiver = line[/^\s*([A-Z]\w*(?:::\w+)*)/, 1]
      next if inline_models.include?(receiver)
      next if receiver.start_with?("ActiveRecord")

      "#{path}:#{i + 1}: #{receiver}.…#{call}"
    end
  end

  def migration_files
    Dir[Rails.root.join("db/migrate/*.rb")]
  end

  # POSITIVE CONTROL 1 — a walker that sees nothing must not pass. These are
  # the lines the fence is claiming to have inspected; if the chain walk
  # breaks, every one of them goes quiet at once and the guard still passes.
  it "sees the data calls the migrations already make" do
    seen = migration_files.sum do |file|
      File.read(file).lines.count { |line| chained_data_call(line) }
    end

    expect(seen).to be >= 15,
      "only #{seen} data calls were recognised across db/migrate — the chain " \
      "walk has stopped reading migration bodies, so an app constant would pass unseen"
  end

  # POSITIVE CONTROL 2 — each shape, including the one #942 was filed for.
  it "catches an app constant reached through a scope chain" do
    planted = <<~RUBY
      Foo.unscoped.update_all(a: 1)
      Foo.where(a: 1).in_batches(of: 500)
      Bar.create!(a: 1)
    RUBY

    expect(offenders_in(planted).size).to eq(3), "a bare shape slipped past the walker"
  end

  # NEGATIVE CONTROL — an inline model is the prescribed fix, so it must clear
  # the fence through the very same chain that condemns the app constant.
  it "clears an inline model reached through the same chain" do
    planted = <<~RUBY
      class MigrationFoo < ActiveRecord::Base
        self.table_name = "foos"
      end
      MigrationFoo.unscoped.update_all(a: 1)
      add_column :foos, :bar, :string
      say_with_time("nothing here") { 1 + 1 }
    RUBY

    expect(offenders_in(planted)).to be_empty
  end

  it "data work in db/migrate uses inline models, not app constants" do
    offenders = migration_files.flat_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      offenders_in(File.read(file), path: relative)
    end

    expect(offenders).to be_empty,
      "Migrations must not reference live app classes — a fork that renames " \
      "the model breaks db:migrate from zero (#449). Define an inline model " \
      "(class MigrationFoo < ActiveRecord::Base; self.table_name = \"foos\") " \
      "and use literal values:\n  #{offenders.join("\n  ")}"
  end
end
