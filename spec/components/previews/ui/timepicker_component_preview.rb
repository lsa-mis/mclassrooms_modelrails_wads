# frozen_string_literal: true

module UI
  # # Time Picker
  #
  # A disclosure button that opens a popover of hour/minute (and, in 12-hour mode,
  # AM/PM) **spinbuttons**, driven by the `timepicker` Stimulus controller. The button
  # is the accessible control (it carries the selected-time label and the offset
  # focus-ring); Escape or an outside click closes the popover.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<button>` trigger with `aria-haspopup="dialog"`,
  #   `aria-expanded` (kept in sync), `aria-controls` → the popover, an i18n accessible
  #   name and a format hint wired via `aria-describedby`; the popover is a
  #   `role="dialog"` named by `label:`; the hour/minute/AM-PM fields are
  #   `role="spinbutton"` with `aria-valuemin`/`max`/`now`/`text` and i18n labels; the
  #   ▲/▼ steppers are decorative (`aria-hidden`, `tabindex=-1`).
  # - **You supply:** an optional `label:` (accessible name), `name:` (to post back),
  #   and `format:` (`:h24` | `:h12`, drives the hour range + the hint; fails loud on an
  #   unknown key).
  # @logical_path Forms & Inputs
  class TimepickerComponentPreview < ViewComponent::Preview
    include UIHelper

    # Standard 24-hour picker: a labelled disclosure button, a format hint, and the
    # hour/minute spinbutton popover. An initial value seeds the spinbuttons.
    def default
    end

    # 12-hour picker: the hour spinbutton caps at 12 and an AM/PM spinbutton appears.
    def twelve_hour
    end

    # Edit `label`, `format`, `step`, and `name` live. `format:` drives BOTH the hour
    # spinbutton range and the human-readable hint (`:h24` → HH:MM 24-hour, `:h12` →
    # HH:MM AM/PM); an unknown key fails loud. `step:` is the minute increment (clamped
    # to 1..60).
    # @param label text
    # @param format select [h24, h12]
    # @param step number
    # @param name text
    def playground(label: "Pick time", format: :h24, step: 5, name: "event[time]")
      ui :timepicker, label: label, format: format.to_sym, step: step.to_i, name: name
    end
  end
end
