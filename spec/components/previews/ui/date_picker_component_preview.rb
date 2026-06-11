# frozen_string_literal: true

module UI
  # # Date Picker
  #
  # A disclosure button that opens an inline calendar popover, driven by the
  # `date-picker` Stimulus controller. The button is the accessible control (it carries
  # the selected-date label and the offset focus-ring); Escape or an outside click
  # closes the popover and returns focus to the trigger. The calendar grid itself is
  # owned by `UI::CalendarComponent`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<button>` trigger with `aria-haspopup="dialog"`,
  #   `aria-expanded` (kept in sync), and `aria-controls` → the popover; a visible
  #   `<label>` caption bound to the trigger plus a format hint wired via
  #   `aria-describedby`; the popover is a `role="dialog"` named by `label:`; the
  #   decorative calendar icon is `aria-hidden`.
  # - **You supply:** an optional `label:` (caption + accessible name), `name:` (to post
  #   back), and `format:` (the display + hint pattern).
  #
  # ## Related
  # `calendar` · `timepicker`
  # @logical_path Forms & Inputs
  class DatePickerComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Standard picker: a labelled disclosure button, a format hint, and the calendar
    # popover. No initial value, so the trigger shows the placeholder.
    def default
    end

    # @!endgroup

    # @!group Reference

    # Edit `label`, `format`, and `name` live. `format:` drives BOTH the initial label's
    # strftime and the human-readable hint (`:long` → MMMM D, YYYY, `:short` → M/D/YYYY,
    # `:iso` → YYYY-MM-DD); an unknown key fails loud.
    # @param label text
    # @param format select [long, short, iso]
    # @param name text
    def playground(label: "Choose date", format: :long, name: "event[date]")
      ui :date_picker, label: label, format: format.to_sym, name: name
    end

    # @!endgroup
  end
end
