# frozen_string_literal: true

require "rails_helper"

# W1-3 (2026-08-22 view-layer audit (internal)): at phone widths a
# preferences-row title rendered twice — once from _preferences_row, once
# from _toggle's own visible label — colliding visually with the row title.
# This is a composition defect wherever a card pairs shared/toggle with
# shared/preferences_row using the same string for both `label:` and
# `title:` — confirmed in both the notification-types card (security, and
# every other category) and the delivery-methods card (in-app, email). The
# redundant toggle label must be suppressed visually (sr-only) since the
# row already shows the title. shared/_quiet_hours_card.html.erb does NOT
# use _preferences_row (custom layout — see its own file comment) and its
# toggle label ("Enable quiet hours") doesn't duplicate the card heading
# ("Quiet hours"), so it's untouched — no collision exists there.
#
# skip_axe_hook: axe runs INSIDE the viewport block instead — the suite-wide
# hook fires after the viewport restore and would audit the desktop layout
# (see spec/support/responsive_viewport.rb).
RSpec.describe "Preferences toggle label at narrow viewports", type: :system, skip_axe_hook: true do
  let(:user) { create(:user) }

  before do
    user.create_preferences!(timezone: "America/New_York")
    sign_in_via_form(user)
  end

  # Cuprite's visible-text/visible? checks only look at
  # display/visibility/opacity; Tailwind's `sr-only` hides via clip-path plus
  # a 1px box, so Cuprite reads it as visible and `have_text(count:)` can't
  # tell the genuinely-visible row title apart from the visually-suppressed
  # toggle label. Assert on the DOM directly instead — the same tactic as
  # spec/system/responsive/tables_overflow_spec.rb's sanctioned
  # computed-style case.
  #
  # data-* hooks, not Tailwind-utility selectors: styling classes carry no
  # semantics and are the first thing a fork restyles.
  def assert_title_rendered_once_visually(title)
    row_title = find("[data-preferences-row-title]", text: title, visible: :all)
    toggle_label = find("[data-toggle-label]", text: title, visible: :all)

    # Token match, not substring: String#include? would pass on `not-sr-only`
    # or a breakpoint-scoped `sm:sr-only`.
    expect(row_title[:class].split).not_to include("sr-only")
    expect(toggle_label[:class].split).to include("sr-only"),
      "expected the toggle's label span to carry sr-only, got class=#{toggle_label[:class].inspect}"

    # Behavioral prong: any correct visually-hidden technique collapses the
    # box to ~1px, whatever class produces it.
    label_width = page.evaluate_script("arguments[0].getBoundingClientRect().width", toggle_label)
    expect(label_width).to be <= 1
  end

  # Unparenthesized reverse-axis predicate = NEAREST ancestor section (the
  # card). The parenthesized form `(…/ancestor::section)[1]` is document
  # order — it selected the OUTERMOST section, the page wrapper, leaving
  # these examples effectively unscoped (panel checkpoint 1).
  def within_card(heading_key)
    card_title_id = "preferences-card-#{I18n.t(heading_key).parameterize}-title"
    within(:xpath, "//*[@id='#{card_title_id}']/ancestor::section[1]") { yield }
  end

  it "shows each preference title exactly once at 375px" do
    with_viewport(ResponsiveViewport::PHONE) do
      visit edit_settings_notification_preferences_path

      title = I18n.t("notifications.preferences.notification_types.items.security.title")
      within_card("notifications.preferences.notification_types.heading") do
        assert_title_rendered_once_visually(title)
      end

      expect(axe_violations_in_both_themes).to be_empty
    end
  end

  it "shows the delivery-methods sibling card's preference title exactly once at 375px" do
    with_viewport(ResponsiveViewport::PHONE) do
      visit edit_settings_notification_preferences_path

      title = I18n.t("notifications.preferences.delivery_methods.items.in_app.title")
      within_card("notifications.preferences.delivery_methods.heading") do
        assert_title_rendered_once_visually(title)
      end
      # Same page and viewport as the sibling example, which already runs the
      # axe audit — auditing twice would only slow the lane.
    end
  end
end
