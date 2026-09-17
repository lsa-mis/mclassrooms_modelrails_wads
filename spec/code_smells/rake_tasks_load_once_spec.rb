# frozen_string_literal: true

require "rails_helper"

# Rake appends an action block to a task each time its .rake file is read, and
# Rake::Task#reenable clears only the invoked flag, not the actions. A second
# `Rails.application.load_tasks` therefore runs every task body twice — and a
# body that calls `abort` raises SystemExit on the second pass, which ends the
# RSpec process mid-example WHILE THE SUMMARY STILL PRINTS "0 failures".
#
# That is the dangerous part and the reason this guard exists: the failure is
# invisible in the one place everyone looks. Before this was fixed,
# `rspec spec/tasks/admin_spec.rb spec/tasks/operators_spec.rb --order defined`
# exited 1 reporting "9 examples, 0 failures" while four examples never ran.
RSpec.describe "Rake tasks are loaded once per process" do
  # Scans one source's stripped-of-comments lines for a bare
  # Rails.application.load_tasks call. Returns the "path:line,line" offender
  # string, or nil when the source has none.
  def offenders_in(source, path)
    lines = without_comments(source).lines
    hits = lines.each_index.select { |i| lines[i].include?("Rails.application.load_tasks") }
    "#{path}:#{hits.map { |i| i + 1 }.join(',')}" if hits.any?
  end

  it "has no direct Rails.application.load_tasks outside the shared loader" do
    loader = "spec/support/rake_tasks.rb"

    offenders = Dir.glob(Rails.root.join("spec/**/*.rb")).filter_map do |path|
      relative = Pathname.new(path).relative_path_from(Rails.root).to_s
      next if relative == loader || relative == "spec/code_smells/rake_tasks_load_once_spec.rb"

      offenders_in(File.read(path), relative)
    end

    expect(offenders).to be_empty, <<~MESSAGE
      Load rake tasks through RakeTasks.load_once (#{loader}), not directly:
        #{offenders.join("\n  ")}
      A second load_tasks duplicates every task's actions; a task that aborts
      then kills the run while RSpec still reports "0 failures".
    MESSAGE
  end

  it "flags a bare call but not the same call inside a comment" do
    offending = "before(:all) { Rails.application.load_tasks }"
    commented = "# before(:all) { Rails.application.load_tasks }"

    expect(offenders_in(offending, "fixture.rb")).to eq("fixture.rb:1")
    expect(offenders_in(commented, "fixture.rb")).to be_nil
  end
end
