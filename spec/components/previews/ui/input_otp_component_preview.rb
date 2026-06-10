# frozen_string_literal: true

module UI
  # # InputOtp
  #
  # A one-time-passcode entry: a labelled `role="group"` of N single-character
  # cells that auto-advance on entry, walk with Arrow/Backspace keys, and accept a
  # full-code paste. Each cell is `inputmode="numeric"` +
  # `autocomplete="one-time-code"` for numeric keypads and OS/browser autofill.
  #
  # ## Use when
  # - You are confirming a code delivered out of band (SMS / email / authenticator)
  #   on a verification screen, posted as `name[0]…name[N-1]`.
  #
  # ## Don't use when
  # - The secret is a free-form password — use `ui :input, type: "password"`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named cell group (`role="group"` + i18n `aria-label`,
  #   default "One-time passcode"), a per-digit i18n label ("Digit N of total") on
  #   each cell, numeric inputmode + one-time-code autocomplete, and the AAA offset
  #   `focus-ring` (never a clipped box-shadow ring). `length` must be positive — a
  #   non-positive value fails loud.
  # - **You supply:** the field `name:`, the digit `length:`, an optional group
  #   `label:`, and an optional `separator:`.
  # @logical_path Forms & Inputs
  class InputOtpComponentPreview < ViewComponent::Preview
    include UIHelper

    # Default — a 6-digit group named "One-time passcode".
    def default
    end

    # Custom length — a 4-digit code with a custom group label.
    def custom_length
    end

    # With a separator — a decorative aria-hidden dash after the 3rd cell.
    def with_separator
    end

    # In a form — cells post as `otp[0]…otp[5]` alongside a submit button.
    def in_a_form
    end
  end
end
