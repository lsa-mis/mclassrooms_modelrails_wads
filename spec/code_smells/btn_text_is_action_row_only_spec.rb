require "rails_helper"

# The .btn-text doctrine (#772). Underline is reserved for in-prose links, so
# it means "link" again: .prose a keeps its underline on hover and only deepens
# text-decoration-color, while .btn-text — used on 17 buttons and 7 links, so
# never a link signal in the first place — carries none. Its hover cue is a
# tinted background per tone, matching .btn-text-icon, which dropped the
# underline for its own reasons in #760.
#
# The rest-state affordance for a tone-less .btn-text is adjacency: every call
# site is a de-emphasized action sitting beside a primary button ("Cancel",
# "Skip", "Dismiss"). That argument holds in an action row and nowhere else,
# which is what the second example fences.
RSpec.describe "btn-text is action-row-only" do
  let(:application_css) { File.read(Rails.root.join("app/assets/tailwind/application.css")) }

  # Walk from `.btn-text {` to its matching close brace. Matching on the exact
  # declaration string keeps `.btn-text-icon {` out of the result. Comments are
  # stripped so these assertions read DECLARATIONS — otherwise a comment that
  # merely names the affordance it dropped fails the rule that dropped it.
  def rule_block(css, selector)
    start = css.index("#{selector} {")
    return nil unless start

    i = css.index("{", start)
    block_start = i
    depth = 0
    loop do
      case css[i]
      when "{" then depth += 1
      when "}" then depth -= 1
      end
      break if depth.zero?
      i += 1
    end
    css[block_start..i].gsub(%r{/\*.*?\*/}m, "")
  end

  describe "the .btn-text rule" do
    subject(:block) { rule_block(application_css, ".btn-text") }

    it "is found, so the absence assertions below scan something real" do
      # Positive control. Without it a renamed class turns every "does not
      # contain" below into a vacuous pass on nil.
      expect(block).to include("focus-ring")
    end

    it "does not underline" do
      expect(block).not_to include("underline"),
        "`.btn-text` declares an underline again. Underline is reserved for " \
        "in-prose links (#772) — it is the one affordance that distinguishes a " \
        "link from a button, and .btn-text is used for both."
    end

    it "carries a hover cue that is not the removal of an underline" do
      # hover:no-underline was the old cue, and it is a latent 1.4.1: in prose
      # it strips the only non-color affordance exactly when the pointer is on
      # the control.
      expect(block).not_to include("hover:no-underline")
      expect(block).to include("hover:bg-"),
        "`.btn-text` needs a visible hover cue. With the underline gone, a " \
        "tinted background is the affordance — the same one .btn-text-icon uses."
    end
  end

  it "is never used in prose content" do
    prose_sources = Dir[Rails.root.join("app/docs/**/*.md")]
    expect(prose_sources).not_to be_empty, "no prose sources found to scan — the guard would pass vacuously"

    offenders = prose_sources.select { |path| File.read(path).include?("btn-text") }

    expect(offenders).to be_empty,
      "btn-text appears in prose:\n  " \
      "#{offenders.map { |p| Pathname.new(p).relative_path_from(Rails.root) }.join("\n  ")}\n" \
      "`.btn-text` is an action-row utility — its rest-state affordance is sitting " \
      "beside a primary button. Dropped into a paragraph it is indistinguishable " \
      "from body text until hovered. Use a plain link in prose; .prose a styles it."
  end
end
