# frozen_string_literal: true

module UI
  # # Banner
  #
  # A prominent page-level announcement strip (promo / cookie / system notice).
  # Renders a labelled `region` landmark and, when `dismissible:`, a real
  # focusable close `<button>`.
  #
  # ## Use when
  # - A standalone, page-level announcement: "We shipped 2.0", a cookie strip, a
  #   scheduled-maintenance heads-up.
  #
  # ## Don't use when
  # - It's an inline message tied to surrounding content — use `alert`.
  # - It's an ephemeral flash — use the app's toast system.
  #
  # ## Accessibility contract
  # - **Guarantees:** a `role="region"` landmark named by an i18n `aria-label`,
  #   AAA-contrast text, and — when `dismissible:` — a real focusable `<button>`
  #   with an i18n accessible name and the `focus-ring` utility.
  # - **You supply:** the message, a valid `variant`, and (for a working dismiss)
  #   the `banner` Stimulus controller, which the gem does not yet ship.
  #
  # ## Variants
  # `default` · `info` · `success` · `warning` · `destructive`
  # @logical_path Feedback & Status
  class BannerComponentPreview < ViewComponent::Preview
    include UIHelper

    # Neutral page-level announcement on the raised surface.
    def default
    end

    # Informational signal on the info-tinted surface.
    def info
    end

    # A dismissible cookie/consent strip — the trailing close button is a real
    # focusable <button> with an i18n accessible name + focus-ring. (Acting on the
    # click needs the `banner` Stimulus controller, which the gem does not yet ship.)
    def dismissible
    end

    # ## Don't — a dismiss control without an accessible name
    #
    # An icon-only close button with no `aria-label` is an unnamed button to screen
    # readers ("button"). The component always names it (i18n "Dismiss"); never
    # hand-roll a bare icon `<button>` in its place.
    # @label Don't · dismiss with no label
    def dont_dismiss_no_label
    end
  end
end
