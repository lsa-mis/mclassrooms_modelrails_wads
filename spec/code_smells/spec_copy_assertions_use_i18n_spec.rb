require "rails_helper"

# In the template the vocabulary tokens resolve to the same words, so a spec
# asserting "Create a workspace" stays green here — and goes red in every fork
# that renamed. Assert copy through I18n.t so the same spec passes in both.
# Model names (Workspace, workspace.name, :workspace factories) are not copy.
#
# Port this to a house RuboCop cop when a FOURTH literal shape appears (#1115).
# Three are already here — matcher, text: option, sentence — and a third noun
# needs no port: the nouns are derived from Vocabulary::NOUNS and an example
# below proves a new one is guarded the day it is added.
RSpec.describe "Code smell: spec copy assertions go through I18n.t" do
  matcher = /\b(have_content|have_text|have_button|have_link|have_title|have_field|click_(?:link|button|on)|fill_in)(?:\(\s*|\s+)(["'])((?:(?!\2).)*)\2/
  text_option = /\btext:\s*(["'])((?:(?!\1).)*)\1/
  # A second shape of the same bug: `eq`/`include`/`match`/`scan` against a
  # literal English sentence (not a view matcher) that names the noun — the
  # activity feed and the project-limit error both asserted this way. Multi-
  # word only (a space in the literal, after stripping any `#{...}` Ruby
  # interpolation) so `workspace.name`-flavored interpolation and single-word
  # identifiers don't trip it.
  sentence_matcher = /\b(eq|include|match|scan)\(\s*(["'])((?:(?!\2).)*)\2/

  def noun_pattern
    /\b(#{Vocabulary::NOUNS.join("|")})s?\b/i
  end

  # Fixture/preview text with no locale key behind it — a Lookbook preview's
  # sample copy or a generic partial spec's arbitrary local. Not app copy, so
  # there is no key to convert to; converting anyway would either invent a
  # fake key or desync the assertion from what's actually rendered. Keep this
  # list a decision, not a fossil.
  allowed = {
    "spec/system/ui/card_component_spec.rb:42" => "preview fixture text, not app copy",
    "spec/system/ui/card_component_spec.rb:43" => "preview fixture text, not app copy",
    "spec/system/ui/dialog_component_spec.rb:60" => "preview fixture text, not app copy",
    "spec/system/ui/timeline_component_spec.rb:34" => "preview fixture text, not app copy",
    "spec/views/shared/section_nav_strip_spec.rb:13" => "arbitrary local passed to a generic partial spec, not app copy",
    "spec/config/vocabulary_fork_spec.rb:38" => "type: :config spec asserting the template's real key against a deliberately absent override — proves defaults are template-owned, not app copy a rename must survive",
    "spec/config/vocabulary_interpolation_spec.rb:39" => "backend-hook mechanism spec; an around block pins the vocabulary to the template's words on purpose",
    "spec/config/vocabulary_interpolation_spec.rb:43" => "backend-hook mechanism spec; an around block pins the vocabulary to the template's words on purpose",
    "spec/config/vocabulary_interpolation_spec.rb:47" => "backend-hook mechanism spec; an around block pins the vocabulary to the template's words on purpose",
    "spec/config/vocabulary_interpolation_spec.rb:48" => "backend-hook mechanism spec; an around block pins the vocabulary to the template's words on purpose",
    "spec/config/vocabulary_interpolation_spec.rb:60" => "backend-hook mechanism spec; an around block pins the vocabulary to the template's words on purpose",
    "spec/config/vocabulary_interpolation_spec.rb:76" => "backend-hook mechanism spec; an around block pins the vocabulary to the template's words on purpose",
    "spec/requests/settings/connected_accounts_spec.rb:623" => "not_to include: regression guard for a literal message already fixed to go through I18n.t — can never render again, in any fork",
    "spec/requests/workspaces_spec.rb:60" => "a workspace's name set by the factory (\"Secret Workspace\"), not UI copy"
  }

  def offenders_in(path, matcher, text_option, sentence_matcher, noun, allowed = {})
    File.readlines(path).each_with_index.filter_map do |line, index|
      location = "#{path.relative_path_from(Rails.root)}:#{index + 1}"
      next if allowed[location]
      # Check for paren/paren-less matcher calls
      m = line.match(matcher)
      if m && m[3].match?(noun)
        "#{location}  #{m[0][0, 70]}"
      # Check for text: option
      elsif (m = line.match(text_option)) && m[2].match?(noun)
        "#{location}  #{m[0][0, 70]}"
      # Check for eq/include/match/scan against a literal sentence
      elsif (m = line.match(sentence_matcher)) && (literal = m[3].gsub(/#\{[^}]*\}/, "")).match?(noun) && literal.include?(" ")
        "#{location}  #{m[0][0, 70]}"
      end
    end
  end

  it "never asserts the bare noun in a text matcher" do
    offenders = Dir.glob(Rails.root.join("spec/**/*_spec.rb"))
      .map { |f| Pathname.new(f) }
      .reject { |p| p.to_s == __FILE__ }
      .flat_map { |p| offenders_in(p, matcher, text_option, sentence_matcher, noun_pattern, allowed) }

    expect(offenders).to be_empty,
      "A spec asserts template copy as a literal English string. Here the placeholder and the " \
      "word match, so it stays green — and goes red in every product that renamed its nouns. " \
      "Fix: assert through I18n.t(\"the.key\") with the arguments the view passes, so one spec " \
      "passes in both. Fixture text with no key behind it goes in `allowed` above, with the reason. " \
      "Read: /docs/developer/i18n (Vocabulary).\n  #{offenders.join("\n  ")}"
  end

  # The allow-list is keyed by file:line and consulted BEFORE the matcher runs
  # (`next if allowed[location]` above), so an entry whose line has moved, or
  # whose offence was fixed, silently protects whatever now sits at that line.
  # Nothing fails; the list just quietly stops describing the code (#1114).
  it "keeps no allow-list entry that has gone stale" do
    stale = allowed.keys.reject do |location|
      file, line = location.split(":")
      path = Rails.root.join(file)
      next false unless path.exist?

      offenders_in(path, matcher, text_option, sentence_matcher, noun_pattern)
        .any? { |offender| offender.start_with?("#{file}:#{line}  ") }
    end

    expect(stale).to be_empty, <<~MESSAGE
      These allow-list entries no longer name a line this gate would flag — the line
      moved, the file went away, or the literal was fixed. Each one now shields
      whatever occupies that line instead. Delete it, or re-point it at the line it
      meant:

        #{stale.join("\n  ")}
    MESSAGE
  end

  it "reports planted literals and ignores model references" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("probe_spec.rb")
      path.write(%(expect(page).to have_content("Create a workspace")\nclick_link "New workspace"\nexpect(page).to have_css("h1", text: "Your workspaces")\nexpect(page).to have_content(workspace.name)\nexpect(activity_log_text).to eq("joined the workspace")\n))

      expect(offenders_in(path, matcher, text_option, sentence_matcher, noun_pattern).size).to eq(4)
    end
  end

  # A third noun must be guarded here the day it is added to Vocabulary::NOUNS.
  it "derives the nouns from Vocabulary::NOUNS" do
    stub_const("Vocabulary::NOUNS", %i[workspace project event])
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("probe_spec.rb")
      path.write(%(expect(page).to have_content("Create an event")\n))

      expect(offenders_in(path, matcher, text_option, sentence_matcher, noun_pattern).size).to eq(1)
    end
  end
end
