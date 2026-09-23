require "rails_helper"

# Tailwind's preflight sets `list-style: none` on `ul`/`ol`, and Safari/VoiceOver
# drop the implicit list role once the marker is gone: no "list, N items" on
# entry, no set position per row, and the list vanishes from the rotor. axe has
# no rule for this browser quirk, so a green audit is not evidence either way —
# a text-level guard is the only thing that can hold the line.
#
# The guard ENUMERATES: it derives the set of list-emitting components from the
# components themselves and fails on any member it cannot classify, so a new
# component cannot reopen the gap by simply not being listed here.
#
# Ported from modelrails_ui's `test_lists_carry_the_list_role.rb` (gem #190/#195)
# alongside the fixes themselves, so the app holds the same line as the gem.
RSpec.describe "Code smell: every list-emitting component restores the list role" do
  # Methods rather than constants: a SCREAMING_CASE assignment inside a describe
  # block defines an Object-level constant, which this suite forbids
  # (spec/code_smells/no_object_level_constants_in_specs_spec.rb).
  def component_root = Rails.root.join("app/components/ui")

  # A list that KEEPS its marker keeps its implicit role and needs no override.
  # Each entry names the utility that restores the marker, so a later sweep can
  # re-check the claim instead of trusting the exemption.
  def exempt = { "error_summary" => "list-disc list-inside" }

  def list_call = /content_tag\(:(?:ul|ol)\b/
  def role_list = /(?:role: "list"|"role" => "list")/

  def components
    Dir[component_root.join("*_component.rb")].sort
  end

  def name_of(file) = File.basename(file, "_component.rb")

  # Comment lines mention `<ul>`/`<ol>` in prose; only real calls count.
  def emitters
    components.filter_map do |file|
      body = File.read(file)
      sites = body.lines.grep_v(/\A\s*#/).join.scan(list_call).length
      [ name_of(file), file, body, sites ] if sites.positive?
    end
  end

  it "restores role=list wherever preflight strips the marker" do
    offenders = emitters.reject { |name, _, body, sites|
      exempt.key?(name) || body.scan(role_list).length >= sites
    }

    expect(offenders.map(&:first)).to be_empty,
      "emits <ul>/<ol> without restoring role=\"list\" (Safari/VoiceOver drop list " \
      "semantics when preflight removes the marker): #{offenders.map(&:first).join(", ")}"
  end

  # An exemption is a claim about the markup, so hold it to the markup.
  it "only exempts components that really do keep their marker" do
    exempt.each do |name, utility|
      file = components.find { |f| name_of(f) == name }

      expect(file).not_to be_nil, "exempt names a component that does not exist: #{name}"
      expect(File.read(file)).to include(utility),
        "#{name} is exempt because of #{utility.inspect}, but does not apply it"
    end
  end

  it "has no stale exemptions" do
    expect((emitters.map(&:first) & exempt.keys).sort).to eq(exempt.keys.sort),
      "exempt names a component that emits no list — drop the stale entry"
  end
end
