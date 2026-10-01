require "rails_helper"
require "set"

# A helper copied into several spec files drifts, and a copy of a spec/support helper silently wins inside
# its own file (#1252, #1273). Define it once under spec/support; same-named helpers that differ may stay.
RSpec.describe "Spec helpers are defined once" do
  let(:helper_definition) { Struct.new(:name, :path, :line, :body) }

  def definitions_in(path, source = File.read(path))
    lines = source.lines
    lines.each_with_index.filter_map do |line, index|
      match = line.chomp.match(/\A(\s*)def (?:self\.)?([a-z_]\w*[?!]?)(.*)\z/) or next
      indent, name, rest = match.captures
      body = if (endless = rest.match(/\A(\(.*?\))?\s*=\s*(.+)\z/))
        [ endless[2].strip ]
      else
        finish = (index + 1...lines.size).find { |k| lines[k].match?(/\A#{indent}end\b/) } or next
        lines[(index + 1)...finish].map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
      end
      helper_definition.new(name, path.to_s.delete_prefix("#{Rails.root}/"), index + 1, body.join("\n"))
    end
  end

  def shadows_in(spec_definitions, support_names)
    spec_definitions.select { |definition| support_names.include?(definition.name) }
  end

  def copies_in(spec_definitions)
    spec_definitions.group_by { |definition| [ definition.name, definition.body ] }.values
      .select { |group| group.map(&:path).uniq.size > 1 }
  end

  let(:spec_definitions) { Dir[Rails.root.join("spec/**/*_spec.rb")].sort.flat_map { |path| definitions_in(path) } }

  # spec/support/harness holds a controller under test, whose actions are not helpers.
  let(:support_names) do
    Dir[Rails.root.join("spec/support/**/*.rb")].reject { |path| path.include?("/spec/support/harness/") }
      .flat_map { |path| definitions_in(path) }.to_set(&:name)
  end

  it "scans real definitions on both sides (floor)" do
    expect(spec_definitions.size).to be > 100
    expect(support_names).to include("expect_aaa_in_both_themes", "balanced_end", "focused_text")
  end

  it "never redefines a spec/support helper inside a spec file" do
    offenders = shadows_in(spec_definitions, support_names)

    expect(offenders).to be_empty,
      "these spec files define a helper spec/support already defines, so the local copy silently wins:\n  " \
      "#{offenders.map { |d| "#{d.path}:#{d.line} #{d.name}" }.join("\n  ")}\n" \
      "Delete the copy and call the shared one; if it must differ, give it its own name."
  end

  it "never copies a helper's body into a second spec file" do
    groups = copies_in(spec_definitions)

    expect(groups).to be_empty,
      "these helpers are defined with the same body in more than one spec file:\n  " \
      "#{groups.map { |g| "#{g.first.name}: #{g.map { |d| "#{d.path}:#{d.line}" }.join(', ')}" }.join("\n  ")}\n" \
      "Move one copy to spec/support and delete the rest, making any difference an explicit argument."
  end

  it "flags a planted copy and a planted shadow (positive control)" do
    source = "  def planted_helper(value)\n    value\n  end\n\n  def balanced_end = :local\n"
    planted = definitions_in("spec/planted_a_spec.rb", source) + definitions_in("spec/planted_b_spec.rb", source)

    expect(copies_in(planted).map { |group| group.first.name }).to include("planted_helper")
    expect(shadows_in(planted, support_names).map(&:name)).to include("balanced_end")
  end
end
