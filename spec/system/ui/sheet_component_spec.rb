# frozen_string_literal: true

# Preview-host accessibility + behavior proof for the sheet (side panel)
# component.
#
# JS-BEHAVIOR pattern: the modal lives in the DOM but stays closed until its
# trigger fires. We OPEN it via the real trigger, audit the LIVE dialog, and
# prove:
#   1. The panel slid IN — its transform is the enter (identity) transform, not
#      the leave (translateX(±100%) or translateY(100%)) transform.
#   2. The native Escape path closes it.
#
# NOTE: axe_clean_in_both_themes? runs axe DEFAULT (AA 4.5:1) locally. The
# authoritative AAA 7:1 audit is the CI-only wcag2aaa after-hook in
# spec/support/playwright_accessibility.rb.
RSpec.describe "Sheet component accessibility", type: :system do
  def open_sheet
    find("[data-action~='click->modal#open']").click
    expect(page).to have_css("dialog[open]")
  end

  # Verifies the panel reached the enter (identity) transform after sliding in.
  # Sheet enter transforms: left/right → translateX(0); top/bottom → translateY(0)
  # Both resolve to the identity matrix. We await the CSS transition to complete
  # before reading the settled value (mirrors PlaywrightAccessibility#set_theme).
  def assert_panel_slid_in
    expect(page).to have_css("dialog[open] [data-modal-target='panel']")

    # Await all CSS transitions on the panel before reading the computed transform.
    cdp_evaluate_async(<<~JS)
      (async () => {
        const panel = document.querySelector("dialog[open] [data-modal-target='panel']");
        if (panel) {
          const transitions = panel.getAnimations().filter(a => a instanceof CSSTransition);
          await Promise.race([
            Promise.allSettled(transitions.map(t => t.finished)),
            new Promise(r => setTimeout(r, 500))
          ]);
        }
        arguments[arguments.length - 1]();
      })();
    JS

    transform = page.evaluate_script(
      "getComputedStyle(document.querySelector(\"dialog[open] [data-modal-target='panel']\")).transform"
    )
    # Enter transform = translateX(0) or translateY(0) → identity matrix.
    # Leave transform = translateX(±100%) / translateY(100%) → non-identity.
    expect(transform).to satisfy("panel must be at enter (identity) transform — got: #{transform}") { |t|
      t == "none" || t == "matrix(1, 0, 0, 1, 0, 0)"
    }
  end

  %w[basic side_left side_bottom].each do |scenario|
    it "#{scenario}: opens, slides in, and passes AAA in both themes" do
      visit "/rails/view_components/ui/sheet_component/#{scenario}"

      # Closed in the DOM until opened — full ARIA scaffolding present either way.
      expect(page).to have_css("dialog[role='dialog'][aria-modal='true']", visible: :all)

      open_sheet
      assert_panel_slid_in

      # Audit the LIVE modal subtree.
      scope = [ "dialog[open]" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  it "closes on the native Escape (cancel) path" do
    visit "/rails/view_components/ui/sheet_component/basic"
    open_sheet

    # cdp_press, not page.send_keys: Cuprite's send_keys clicks the active element (the
    # focused dialog panel) before typing, which fails here — the click coordinates land
    # outside anything clickable while the native <dialog> is open.
    cdp_press("Escape")

    expect(page).to have_no_css("dialog[open]")
  end
end
