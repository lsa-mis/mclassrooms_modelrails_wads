# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::SwitchComponent, type: :component do
  it "renders a native checkbox with role=switch" do
    render_inline(described_class.new(name: "notifications"))

    expect(page).to have_css("input[type='checkbox'][role='switch']")
  end

  # The bug fix: a static aria-checked goes stale on toggle, so it must not exist
  # anywhere — the native checkbox `checked` conveys switch state under role=switch.
  it "has no static aria-checked attribute" do
    render_inline(described_class.new(name: "notifications", checked: true))

    expect(page).not_to have_css("[aria-checked]")
  end

  # STRUCTURAL CASCADE GUARD: the visual track/thumb react to the input via Tailwind
  # `peer-*` utilities, which compile to the subsequent-sibling combinator
  # (`.peer:checked ~ .x`). That only matches LATER SIBLINGS of the input — never
  # descendants of a sibling. So a span MUST appear as a later sibling of the
  # role=switch input, or peer-checked:/peer-focus-visible:/peer-disabled: silently
  # no-op and the switch renders frozen OFF with no focus ring (the bug).
  it "renders track/thumb as later siblings of the peer input" do
    render_inline(described_class.new(checked: true))

    expect(page).to have_css("input[role='switch'][type='checkbox'] ~ span")
  end

  it "sets native checked on the input when checked" do
    render_inline(described_class.new(name: "notifications", checked: true))

    expect(page).to have_css("input[type='checkbox'][role='switch'][checked]")
  end

  it "omits native checked when unchecked" do
    render_inline(described_class.new(name: "notifications"))

    expect(page).not_to have_css("input[checked]")
  end

  # The clickable track <label for> must point at the input id — clicking the
  # track toggles the control (association + click target).
  it "associates the track label with the input" do
    render_inline(described_class.new(id: "notify_switch"))

    expect(page).to have_css("input#notify_switch[type='checkbox']")
    expect(page).to have_css("label[for='notify_switch']")
  end

  # AAA 2.5.5 target size: the clickable track label carries a >=44px hit area.
  it "renders a clickable track label meeting the 44px target" do
    render_inline(described_class.new(id: "notify_switch"))

    expect(page).to have_css("label.min-h-input.min-w-11")
  end

  it "sets aria-invalid on the input when invalid" do
    render_inline(described_class.new(name: "notifications", invalid: true))

    expect(page).to have_css("input[type='checkbox'][aria-invalid='true']")
  end

  it "omits aria-invalid when invalid is false" do
    render_inline(described_class.new(name: "notifications"))

    expect(page).not_to have_css("input[aria-invalid]")
  end

  # The TRACK carries a peer-aria-invalid danger BORDER so an invalid switch is
  # visible (the peer input gets aria-invalid; the later-sibling track reacts).
  # A border rather than a ring because forced-colors does not paint a
  # box-shadow, and this control had NO invalid state there at all before
  # (modelrails_ui #258).
  it "thickens the track's border for the peer-aria-invalid state" do
    render_inline(described_class.new(name: "notifications"))

    expect(page).to have_css('span.peer-aria-invalid\\:border-2.peer-aria-invalid\\:border-danger')
  end

  it "sets aria-describedby on the input when describedby is given" do
    render_inline(described_class.new(name: "notifications", describedby: "notify_hint"))

    expect(page).to have_css("input[type='checkbox'][aria-describedby='notify_hint']")
  end

  it "omits aria-describedby when describedby is absent" do
    render_inline(described_class.new(name: "notifications"))

    expect(page).not_to have_css("input[aria-describedby]")
  end

  # An empty describedby must not leak aria-describedby="" (present? guard, matching
  # the sibling components).
  it "omits aria-describedby when describedby is blank" do
    render_inline(described_class.new(name: "notifications", describedby: ""))

    expect(page).not_to have_css("input[aria-describedby]")
  end

  # Component attrs win over caller **html_attrs: a caller must not be able to clobber
  # role="switch" or the aria-* the component sets (a11y guarantee, matching select).
  it "lets component attrs win over caller html attrs" do
    render_inline(described_class.new(name: "notifications", invalid: true, role: "checkbox"))

    expect(page).to have_css("input[role='switch']")
    expect(page).not_to have_css("input[role='checkbox']")
    expect(page).to have_css("input[aria-invalid='true']")
  end

  it "falls back the id when no id or name is given" do
    render_inline(described_class.new)

    expect(page).to have_css("input[type='checkbox'][role='switch']")
    expect(page).to have_css("label[for^='switch_']")
  end

  it "renders a text label associated with the input" do
    render_inline(described_class.new(id: "notify_switch", label: "Email notifications"))

    expect(page).to have_css("label[for='notify_switch']", text: "Email notifications")
  end
end
