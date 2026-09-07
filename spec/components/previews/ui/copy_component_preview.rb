# frozen_string_literal: true

module UI
  # # Copy
  #
  # A readonly value — a share link, a token, an ID — with a button that copies it
  # to the clipboard and confirms twice: a check glyph, and a status region that
  # assistive technology announces. A failed copy selects the value and says so,
  # assertively; it never claims a success the browser did not confirm.
  #
  # ## Use when
  # - The user needs to paste a value somewhere else: an invitation URL, an API token,
  #   an identifier.
  #
  # ## Don't use when
  # - A person must read or transcribe the value rather than paste it — the single-line
  #   input scrolls a long value.
  # - The value is editable.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<label for>` on the value; the trigger's accessible name
  #   is "Copy <label>" and its visible text never changes (WCAG 2.5.3); polite and
  #   assertive regions exist empty from first render; 44 px targets; no motion.
  # - **You supply:** `label:` as the noun for the value ("Invitation link") and, if
  #   you translate, the four `modelrails_ui.copy.*` keys.
  #
  # ## Related
  # `input` holds the value; `button` is the trigger cell; `kbd` shows a key rather
  # than copying one.
  # @logical_path Forms & Inputs
  class CopyComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # A share link with a visible label. Press Copy: the check glyph appears and the
    # status line reads "Copied Invitation link to the clipboard".
    def default
    end

    # A long value scrolls inside the input; it never wraps the page.
    def long_value
    end

    # The label is still there for assistive technology — `sr-only` — when the
    # surrounding UI already names the value.
    def label_hidden
    end

    # Two controls on one page stay independent: distinct ids, and each announcement
    # names its own value.
    def two_on_one_page
    end

    # @!endgroup

    # @!group Reference

    # @param value text
    # @param label text
    # @param label_hidden toggle
    def playground(value: "https://example.test/invitations/abc123/accept", label: "Invitation link", label_hidden: false)
      ui :copy, value: value, label: label, label_hidden: label_hidden
    end

    # ## Don't — a label swap as the only confirmation
    #
    # Swapping the button's text to "Copied!" is invisible to a screen reader (no live
    # region), breaks label-in-name for the feedback window, and the hand-rolled fallback
    # usually announces success it never confirmed. Use `ui :copy`.
    # @label Don't · label swap, no live region
    def dont_visual_only_confirmation
    end

    # @!endgroup
  end
end
