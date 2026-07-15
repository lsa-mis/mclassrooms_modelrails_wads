# frozen_string_literal: true

# Preview-host accessibility + behavior proof for the drawer (bottom sheet)
# component.
#
# JS-BEHAVIOR pattern: the modal lives in the DOM but stays closed until its
# trigger fires. We OPEN it via the real trigger, audit the LIVE dialog, and
# prove:
#   1. The panel slid IN — its transform is the enter (identity) transform, not
#      the leave (translateY(100%)) transform.
#   2. The native Escape path closes it.
#
# NOTE: axe_clean_in_both_themes? runs axe DEFAULT (AA 4.5:1) locally. The
# authoritative AAA 7:1 audit is the CI-only wcag2aaa after-hook in
# spec/support/playwright_accessibility.rb.
RSpec.describe "Drawer component accessibility", type: :system do
  def open_drawer
    find("[data-action~='click->modal#open']").click
    expect(page).to have_css("dialog[open]")
  end

  %w[basic with_footer].each do |scenario|
    it "#{scenario}: opens, slides in, and passes AAA in both themes" do
      visit "/rails/view_components/ui/drawer_component/#{scenario}"

      # Closed in the DOM until opened — full ARIA scaffolding present either way.
      expect(page).to have_css("dialog[role='dialog'][aria-modal='true']", visible: :all)

      open_drawer

      # Wait for the panel to exist, then await the CSS transition to complete.
      # The modal controller animates from leaveTransform → enterTransform
      # (translateY(0) for drawer) over --modal-animation-duration (default 200ms).
      expect(page).to have_css("dialog[open] [data-modal-target='panel']")

      # Await all CSS transitions on the panel, then read the settled transform.
      # This mirrors the same pattern used in PlaywrightAccessibility#set_theme.
      cdp_evaluate_async(<<~JS)
        const done = arguments[arguments.length - 1];
        const panel = document.querySelector("dialog[open] [data-modal-target='panel']");
        if (!panel) { done(); return; }
        const transitions = panel.getAnimations().filter(a => a instanceof CSSTransition);
        Promise.race([
          Promise.allSettled(transitions.map(t => t.finished)),
          new Promise(r => setTimeout(r, 500))
        ]).then(() => done());
      JS

      transform = page.evaluate_script(
        "getComputedStyle(document.querySelector(\"dialog[open] [data-modal-target='panel']\")).transform"
      )
      # Drawer enter transform = translateY(0) → identity matrix.
      # Leave transform = translateY(100%) → matrix with non-zero Y translation.
      expect(transform).to satisfy("panel must be at enter (identity) transform — got: #{transform}") { |t|
        t == "none" || t == "matrix(1, 0, 0, 1, 0, 0)"
      }

      # Audit the LIVE modal subtree.
      scope = [ "dialog[open]" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  it "closes on the native Escape (cancel) path" do
    visit "/rails/view_components/ui/drawer_component/basic"
    open_drawer

    cdp_press(:escape)

    expect(page).to have_no_css("dialog[open]")
  end
end
