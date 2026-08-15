require "rails_helper"

# Constants assigned inside an RSpec describe block land on Object, shared by
# every spec file a worker loads. Two same-named constants in different files
# silently clobber each other (load-time warning only), producing failures
# that depend on CI's worker sharding: green locally, red in CI. This caught
# us on 2026-08-14 — two code_smells specs both defined ALLOWED (a Hash and
# an Array); CI grouped them into one worker and the immutability check
# failed with NoMethodError on the wrong object (#607 fixed the pair, #608
# swept the rest). Use plain locals in the describe body, or `let` when a
# helper def needs the value; spec/support modules are exempt because their
# constants are namespaced.
RSpec.describe "Code smell: no Object-level constants in spec files" do
  constant_assignment = /^\s*[A-Z][A-Z_0-9]*\s*=[^=~]/
  namespace_opener = /^(\s*)(?:module|class)\s+[A-Z]/

  # Line ranges inside an explicit `module Foo`/`class Foo` body are exempt:
  # constants there are namespaced (Foo::CONST), not Object-level. Extents are
  # found by the same indentation-matching this suite's AuthorizationAudit
  # helper uses for method bodies.
  namespaced_ranges = lambda do |lines|
    lines.each_with_index.filter_map do |line, i|
      next unless (m = line.match(namespace_opener))

      indent = m[1].length
      close = (i + 1...lines.size).find { |j| lines[j] =~ /^\s{#{indent}}end\b/ }
      (i..(close || lines.size - 1))
    end
  end

  it "spec files define no bare SCREAMING_CASE constants" do
    offenders = Dir[Rails.root.join("spec/**/*_spec.rb")].flat_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      lines = File.readlines(file)
      exempt = namespaced_ranges.call(lines)

      lines.each_with_index.filter_map do |line, i|
        next unless line.match?(constant_assignment)
        next if exempt.any? { |range| range.cover?(i) }

        "#{relative}:#{i + 1}: #{line.strip}"
      end
    end

    expect(offenders).to be_empty,
      "Bare constants in describe blocks land on Object and collide across " \
      "parallel workers (the #607 incident). Use a local in the describe " \
      "body, or `let` if a helper def needs it:\n  #{offenders.join("\n  ")}"
  end
end
