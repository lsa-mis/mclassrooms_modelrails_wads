require "rails_helper"

# The `-strong` signal tokens are graphics colors, not text colors. Their own
# definition says so — app/assets/tailwind/tokens/_signals.css on
# --color-danger-strong: "Fire-engine red for graphics + opt-in elements. L=0.65
# sits below the AAA text threshold (~4-5:1 on slate-950, AA only) — DO NOT use
# for general text content."
#
# Used as a text color they measure ~4.5:1 where AAA needs 7:1, and the sibling
# --color-danger is tuned for exactly that job (axe-measured 7.08:1 on the
# lightest dark surface). Two views had drifted onto the wrong one; axe caught
# only the one that a system spec happened to render in dark mode, so the
# violation is cheaper to forbid at the source than to rely on coverage.
#
# BORDERS and ICONS are fine and deliberately allowed: WCAG 1.4.11 applies 3:1
# to non-text contrast, which is what the token was designed against.
# The companion runtime gate. Both of these exist because of #541: a real AAA
# violation reached main under a green CI, and the two reasons were that the
# audit only ran on CI and only ever saw one theme.
RSpec.describe "the accessibility audit is a real gate" do
  let(:source) { File.read(Rails.root.join("spec/support/playwright_accessibility.rb")) }

  it "audits everywhere, not only on CI" do
    expect(source).not_to match(/^\s*if ENV\["CI"\]/),
      "the per-example axe hook is gated on ENV[\"CI\"] again. Gating it means a " \
      "developer gets no accessibility feedback until they push, which is how the " \
      "contrast bug in #540 reached main. Keep it opt-OUT (SKIP_AXE=1)."
  end

  it "sets the theme explicitly rather than auditing whatever was left behind" do
    hook = source[/config\.after\(:each, type: :system\).*/m].to_s

    expect(hook).to include("set_theme"),
      "the axe hook audits whatever theme the example happened to leave the page in, " \
      "which makes the verdict depend on test choreography rather than the UI — the " \
      "same command catches a violation on one run and misses it on the next (#541)."
  end
end

RSpec.describe "signal -strong tokens are never used as text colors" do
  TEXT_UTILITY = /(?<![\w-])(?:dark:)?text-(?:danger|warning|success|info)-strong(?![\w-])/

  # Icons are graphics, judged against 1.4.11's 3:1, not 1.4.6's 7:1.
  ALLOWED = [
    # Tints a danger glyph in the dialog, not a label.
    "app/views/shared/_confirm_dialog.html.erb",
    # The bell IS the indicator — the helper documents why red alone needs
    # `-strong` there (the AAA dark red reads coral at bell size).
    "app/helpers/notification_bell_helper.rb"
  ].freeze

  it "uses the AAA-tuned base token for text, not the graphics -strong variant" do
    sources = Dir[Rails.root.join("app/views/**/*.erb")] +
              Dir[Rails.root.join("app/components/**/*.{rb,erb}")] +
              Dir[Rails.root.join("app/helpers/**/*.rb")]

    offenders = sources.filter_map do |path|
      relative = Pathname.new(path).relative_path_from(Rails.root).to_s
      next if ALLOWED.include?(relative)

      hits = File.read(path).lines.each_with_index.filter_map do |line, i|
        "#{relative}:#{i + 1}" if line.match?(TEXT_UTILITY)
      end
      hits.presence
    end.flatten

    expect(offenders).to be_empty, <<~MSG
      `text-*-strong` is a graphics color used as a text color at:
        #{offenders.join("\n  ")}

      Those measure roughly 4.5:1 against their tinted surface where WCAG AAA
      needs 7:1. Use the base token (`text-danger`, `text-warning`, …), which is
      tuned for text on dark surfaces. Borders and icons may keep `-strong`;
      add the file to ALLOWED here if the usage is genuinely non-text.
    MSG
  end
end
