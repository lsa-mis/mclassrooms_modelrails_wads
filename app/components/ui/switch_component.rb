# frozen_string_literal: true

module UI
  # # Switch
  #
  # A binary on/off toggle backed by a native `<input type="checkbox" role="switch">`.
  # The visually-hidden checkbox is the `peer`; a clickable track `<label>` and an
  # `aria-hidden` thumb render the visual switch and react via `peer-checked:` /
  # `peer-focus-visible:` / `peer-disabled:`.
  #
  # ## Use when
  # - You need an immediate on/off setting (notifications on, dark mode on) that takes
  #   effect on toggle — not a value collected for later form submission.
  #
  # ## Don't use when
  # - The choice is part of a form the user submits, or it isn't strictly binary —
  #   use a checkbox or radio group instead.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `role="switch"` checkbox whose **native `checked` state**
  #   conveys on/off to assistive tech (no JS, no stale ARIA), and a >=44px clickable
  #   target (AAA 2.5.5) even though the visual track is smaller.
  # - **You supply:** an accessible name via `label:` (or `aria-label:` on a label-less
  #   switch), the initial `checked:` state, and a `name:` so the value posts.
  #
  # ## State
  # `checked:` (default `false`) sets the initial on/off; the native checkbox tracks
  # the rest. No variant axis, so no fail-loud guard is needed.
  class SwitchComponent < ApplicationComponent
    # The OUTER <label for=@id> is the >=44px click target (AAA 2.5.5): a transparent
    # flex box that centers the smaller visual switch, so the hit area grows without
    # enlarging the graphic. The `for` association toggles the input regardless of DOM
    # nesting. has-[:disabled]: is a cosmetic cursor nicety (the label is an ancestor,
    # not a peer, so peer-* can't reach it — the real peer-disabled: hooks live on TRACK).
    TARGET  = "relative inline-flex min-h-11 min-w-11 shrink-0 cursor-pointer items-center justify-center " \
              "has-[:disabled]:cursor-not-allowed"
    # WRAPPER keeps the original switch size; the input + TRACK + THUMB are siblings
    # inside it so the input is the `peer` and TRACK/THUMB are its LATER SIBLINGS —
    # the only DOM order in which Tailwind peer-* (`.peer:checked ~ .x`) matches.
    WRAPPER = "relative inline-flex h-[1.15rem] w-8 shrink-0"
    TRACK   = "pointer-events-none absolute inset-0 rounded-full border border-transparent shadow-xs " \
              "transition-all bg-surface-sunken peer-checked:bg-interactive " \
              "peer-focus-visible:[outline:2px_solid_var(--color-interactive-focus)] peer-focus-visible:[outline-offset:2px] " \
              "peer-aria-invalid:ring-2 peer-aria-invalid:ring-danger " \
              "peer-disabled:opacity-50"
    THUMB   = "pointer-events-none absolute inset-y-0 left-px my-auto z-10 block size-4 rounded-full " \
              "bg-surface-raised ring-0 transition-transform " \
              "translate-x-0 peer-checked:translate-x-[calc(100%-2px)]"

    def initialize(label: nil, checked: false, invalid: false, describedby: nil, **html_attrs)
      @label = label
      @checked = checked
      @invalid = invalid
      @describedby = describedby
      @id = html_attrs[:id] || html_attrs[:name]&.gsub(/\W/, "_") || "switch_#{object_id}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, class: cn("inline-flex items-center gap-2", @extra_class)) do
        concat switch_widget
        concat text_label if @label
      end
    end

    private

    def switch_widget
      # The OUTER <label for=@id> is the >=44px click target; the `for` association
      # toggles the input regardless of nesting. The visual switch is the inner WRAPPER:
      # input (the peer) followed by its LATER SIBLINGS, the track and thumb — the DOM
      # order Tailwind peer-* requires (`.peer:checked ~ .x` is a sibling combinator).
      content_tag(:label, for: @id, class: TARGET) do
        content_tag(:span, nil, class: WRAPPER) do
          # Component attrs (role/type/aria-*) are applied AFTER @html_attrs so the
          # caller can't clobber the a11y contract (role="switch" and the aria-* we set).
          input_attrs = @html_attrs.merge(type: "checkbox", id: @id, class: "peer sr-only", role: "switch")
          # No explicit aria-checked: the native checkbox `checked` conveys switch state
          # under role=switch; a static aria-checked went stale on toggle (the bug we fixed).
          # No JS needed; the app's 0b axe gate verifies.
          input_attrs[:checked] = true if @checked
          input_attrs["aria-invalid"] = "true" if @invalid
          input_attrs["aria-describedby"] = @describedby if @describedby.present?
          concat content_tag(:input, nil, **input_attrs)
          concat content_tag(:span, nil, class: TRACK)
          concat content_tag(:span, nil, class: THUMB, "aria-hidden": "true")
        end
      end
    end

    def text_label
      content_tag(:label, @label,
        for: @id,
        class: "cursor-pointer text-sm font-medium leading-none")
    end
  end
end
