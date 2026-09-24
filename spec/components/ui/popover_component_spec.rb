# frozen_string_literal: true

require "rails_helper"

# `trigger_attrs:` exists so a caller can mark the trigger — a popover standing in
# for one option of a control group has to announce that it is the current choice
# the way its sibling buttons do.
#
# The merge is the whole subtlety. `content_tag` de-duplicates neither `:key`
# against `"key"` nor the reverse, and a flat merge drops a caller's `data:` hash
# entirely because the component sets `data:` too and the last write wins. Both
# failures are silent, which is why they are pinned here rather than left to a
# reviewer to notice.
RSpec.describe UI::PopoverComponent, type: :component do
  def render_popover(**opts)
    render_inline(described_class.new(label: "Date range", id: "pop", **opts)) do |pop|
      pop.with_trigger { "Open" }
    end
  end

  def trigger_tag = rendered_content[/<button[^>]*>/]

  it "puts caller attributes on the trigger, not the wrapper" do
    render_popover(trigger_attrs: { "aria-current": "true" })

    expect(page).to have_css("button[aria-current=true]", visible: :all)
  end

  it "keeps its own contract when a caller tries to overwrite it" do
    render_popover(trigger_attrs: { "aria-expanded": "true", type: "submit", "aria-controls": "elsewhere" })

    expect(page).to have_css("button[aria-expanded=false]", visible: :all)
    expect(page).to have_css("button[type=button]", visible: :all)
    expect(page).to have_no_css("button[aria-controls=elsewhere]", visible: :all)
  end

  # THE TRAP. A flat merge drops this silently — the hook simply never appears and
  # nothing explains why. The reference for this is gem #204.
  it "keeps a caller's data: alongside its own Stimulus wiring" do
    render_popover(trigger_attrs: { data: { focus_key: "range" } })

    expect(page).to have_css("button[data-focus-key=range]", visible: :all)
    expect(page).to have_css("button[data-floating-target=trigger]", visible: :all)
  end

  it "still wins where a caller's data: key genuinely collides" do
    render_popover(trigger_attrs: { data: { floating_target: "panel" } })

    expect(page).to have_css("button[data-floating-target=trigger]", visible: :all)
  end

  # Presence assertions pass on the duplicated output and Nokogiri collapses the
  # duplicate before a selector ever sees it, so this counts in the raw string.
  it "never emits an attribute twice, whichever key shape the caller used" do
    render_popover(trigger_attrs: { "aria-expanded": "true" })

    expect(trigger_tag.scan(/\saria-expanded=/).length).to eq(1), trigger_tag
  end

  it "adds nothing when no trigger_attrs are given" do
    render_popover

    expect(page).to have_css("button[data-floating-target=trigger]", visible: :all)
    expect(page).to have_no_css("button[aria-current]", visible: :all)
  end
end
