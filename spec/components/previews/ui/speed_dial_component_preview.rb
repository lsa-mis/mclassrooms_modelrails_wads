# frozen_string_literal: true

module UI
  # # Speed dial
  #
  # A floating action button (FAB) that expands into a stack of sub-actions — the
  # classic Material "speed dial". The FAB anchors to a screen corner; tapping it
  # discloses the action panel, driven by the `speed-dial` Stimulus controller.
  #
  # ## Accessibility contract
  # - **Guarantees:** the FAB is a disclosure trigger — i18n accessible name
  #   (`label:` to override), `aria-expanded` synced to the open state, and
  #   `aria-controls` pointing at the hidden action panel. The FAB and every action
  #   carry the AAA offset `focus-ring`. The `+` glyph is decorative (`aria-hidden`).
  # - **You supply:** actions (label + optional href; an href renders an `<a>`,
  #   otherwise a `<button>`).
  # - **Fail-loud:** an unknown `position:` raises in dev.
  # @logical_path Actions
  class SpeedDialComponentPreview < ViewComponent::Preview
    include UIHelper

    # The default bottom-right dial with three actions. The panel is collapsed until
    # the FAB is activated.
    #
    # @param position select { choices: [bottom_right, bottom_left, bottom_center] }
    def default(position: :bottom_right)
      render_with_template(locals: { position: position.to_sym })
    end
  end
end
