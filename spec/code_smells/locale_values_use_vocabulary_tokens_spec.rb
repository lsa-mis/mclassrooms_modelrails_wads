require "rails_helper"

# A fork renames the product's nouns in config/vocabulary.local.yml. That only
# holds if upstream strings say %{workspace}, never "workspace": every literal
# that lands upstream is a string the fork silently ships in the wrong word
# (the real fork did — its onboarding wizard still said "workspace" after it
# renamed to Event). Fork-owned locale files are exempt: a fork rewrites them.
# Every other file is governed, the ones a fork adds included — a fork's own
# strings follow its rename only if they use the placeholder too.
RSpec.describe "Code smell: locale values use the vocabulary placeholders" do
  fork_owned = %w[brand.en.yml pages.en.yml]
  # The literal is the word, not the noun. Keep this list a decision, not a fossil.
  allowed = {
    # "file.en.yml:LINE" => "reason the bare noun on this line is not app copy"
  }

  def teach(offenders)
    placeholders = Vocabulary.tokens.keys.map { |token| "%{#{token}}" }.join(" ")
    <<~MSG
      A locale value spells out a noun this app treats as a placeholder:

        #{offenders.join("\n  ")}

      Products built on this codebase rename their nouns once, in
      config/vocabulary.local.yml (project → team, workspace → course). A string
      written with the placeholder follows; a string written with the word keeps
      saying "project" in that product. Nothing crashes — it just reads wrong,
      and nobody is told. The rule covers every locale file here, yours included.

      Fix: write the placeholder — "Archive this %{project}?" — and the rest is
      automatic. Placeholders: #{placeholders}
      Not the product's noun on that line (a proper name, a code sample)? Add it
      to `allowed` at the top of this spec with the reason. A fork should prefer
      the placeholder: spec/ is not fork-owned, so that edit conflicts on sync.
      Read: /docs/developer/i18n (Vocabulary).
    MSG
  end

  def offenders_in(path, nouns, allowed)
    File.readlines(path).each_with_index.filter_map do |line, index|
      # Skip comment lines
      next if line.match?(/\A\s*#/)
      # Skip blank lines
      next if line.match?(/\A\s*\z/)
      # Skip key-only lines (the noun here is a key, not copy)
      next if line.match?(/\A\s*[\w.-]+:\s*(\||>[-+]?)?\s*\z/)

      # Extract value from key: value lines. `/m` lets `.` cross the trailing
      # newline `File.readlines` leaves on; `match?` never sets `Regexp.last_match`,
      # so capture from `match` directly rather than reading stale global state.
      if (m = line.match(/\A\s*[\w.-]+:\s+(.+)\z/m))
        scannable = m[1]
      else
        # Block-scalar continuation or array entry - scan the whole line
        scannable = line
      end

      scannable = scannable.gsub(/%\{[^}]*\}/, "")
      hit = nouns.find { |noun| scannable.match?(/\b#{noun}s?\b/i) }
      next unless hit
      location = "#{path.basename}:#{index + 1}"
      next if allowed[location]
      "#{location}  (#{hit}) #{line.strip[0, 80]}"
    end
  end

  it "says %{workspace} / %{project} and never the bare word" do
    nouns = Vocabulary::NOUNS.map(&:to_s)
    offenders = Dir.glob(Rails.root.join("config/locales/en/*.yml"))
      .map { |f| Pathname.new(f) }
      .reject { |p| fork_owned.include?(p.basename.to_s) }
      .flat_map { |p| offenders_in(p, nouns, allowed) }

    expect(offenders).to be_empty, teach(offenders)
  end

  # The one reader who meets this cold is a fork developer adding their own
  # locale file. The message has to carry the whole lesson.
  it "teaches the rule when it fails: the line, every placeholder, the fork's file, and the doc" do
    message = teach([ "probe.en.yml:3  (project) confirm: \"Archive this project?\"" ])

    expect(message).to include("probe.en.yml:3")
    Vocabulary.tokens.keys.each { |token| expect(message).to include("%{#{token}}") }
    expect(message).to include("config/vocabulary.local.yml").and include("/docs/developer/i18n")
    expect(message).not_to include("upstream-owned")
  end

  # The check must be able to fail.
  it "reports a planted literal and block-scalar lines" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("probe.en.yml")
      path.write(%(en:\n  probe: "Create a workspace"\n  fine: "Create %{Workspace}"\n  workspaces:\n    body: |\n      Ask your workspace administrator.\n    ok: "Nothing here"\n))

      expect(offenders_in(path, %w[workspace project], {})).to contain_exactly(
        a_string_starting_with("probe.en.yml:2"),
        a_string_starting_with("probe.en.yml:6")
      )
    end
  end
end
