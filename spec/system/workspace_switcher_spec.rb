# frozen_string_literal: true

require "rails_helper"

# System spec for the header workspace switcher (Phase 2b Task 1).
#
# The switcher is `hidden md:block` — visible only at the md breakpoint and above.
# Playwright's default viewport (1280×720) satisfies this; no resize is needed.
#
# Escape is dispatched via the dropdown controller's handleKeydown directly,
# matching the pattern in user_menu_spec.rb — programmatic KeyboardEvent dispatch
# does not reach main-world Stimulus listeners in Playwright's isolated context.
#
# Per-spec axe runs AA locally; the AAA 7:1 audit is the CI-only wcag2aaa hook.
# Do not claim AAA from a local run.
RSpec.describe "Workspace switcher (header)", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let!(:second) do
    ws = create(:workspace)
    create(:membership, :owner, user: user, workspace: ws)
    ws
  end

  # Dispatch a KeyboardEvent directly to the dropdown Stimulus controller.
  # Reuses the same technique as user_menu_spec.rb.
  def send_switcher_key(key)
    cdp_execute(<<~JS)
      (function() {
        var el = document.querySelector('#workspace-switcher-button').closest('[data-controller~="dropdown"]');
        var c = window.Stimulus.getControllerForElementAndIdentifier(el, 'dropdown');
        if (c) c.handleKeydown(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }));
      })()
    JS
  end

  before do
    sign_in_via_form(user)
    visit workspaces_path
  end

  it "opens on click, lists both workspaces, and navigates on selection" do
    button = find("#workspace-switcher-button")
    expect(button["aria-expanded"]).to eq("false")

    button.click
    expect(button["aria-expanded"]).to eq("true")

    within "#workspace-switcher-menu" do
      expect(page).to have_link(second.name)
      click_link second.name
    end

    expect(page).to have_current_path(workspace_path(second))
  end

  it "closes on Escape" do
    find("#workspace-switcher-button").click
    expect(find("#workspace-switcher-button")["aria-expanded"]).to eq("true")

    send_switcher_key("Escape")

    expect(find("#workspace-switcher-button")["aria-expanded"]).to eq("false")
    expect(page).to have_no_css("#workspace-switcher-menu", visible: :visible)
  end

  it "is accessible with the menu open (wcag2aaa-scoped, both themes)" do
    find("#workspace-switcher-button").click
    expect(find("#workspace-switcher-button")["aria-expanded"]).to eq("true")

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
