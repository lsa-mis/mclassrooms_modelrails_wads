# frozen_string_literal: true

module UI
  # # Dialog
  #
  # A native `<dialog>` modal with focus-trapping, `aria-modal`, and an accessible
  # close button. Behavior is driven by the `modal` Stimulus controller that ships
  # alongside this component.
  #
  # **In most views, render via the shared partial:**
  # `render "shared/modal", title: "Edit profile", size: :lg do … end`
  # The partial wraps `UI::DialogComponent` and wires the proven `modal` controller.
  # Use `ui :dialog` directly only when you need programmatic control or are building
  # a custom wrapper.
  #
  # ## Use when
  # - You need a focus-trapped modal for a confirmation, form, or detail overlay.
  # - You are building a custom wrapper around `UI::DialogComponent` (pass `wrapper: false`
  #   and manage the `data-controller="modal"` yourself).
  #
  # ## Don't use when
  # - The action is a destructive non-GET — keep the submit inside a `button_to` form;
  #   the dialog is the container, not the action mechanism.
  # - You need a toast or non-blocking notification — use the notification system instead.
  #
  # ## Accessibility contract
  # - **Guarantees:** native `<dialog>` semantics — `role="dialog"`, `aria-modal="true"`,
  #   `aria-labelledby` wired to the heading, `aria-describedby` wired when `description:`
  #   is supplied, an accessible close button, and focus management via the `modal`
  #   Stimulus controller.
  # - **You supply:** a `title:` (required — it is the accessible name via `aria-labelledby`).
  #   When using `wrapper: true` (the default), the `with_trigger` slot provides the
  #   open button; `wrapper: false` requires you to supply `data-controller="modal"` on
  #   a parent element and wire your own trigger.
  #
  # ## Related
  # `alert_dialog` · `drawer` · `sheet`
  # @logical_path Overlays
  class DialogComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Renders spec/components/previews/ui/dialog_component_preview/basic.html.erb —
    # the complete, copy-paste snippet shown in Lookbook's Source tab.
    def basic; end

    # Edit-modal pattern: form fields inside a dialog using TailwindFormBuilder.
    # Renders spec/components/previews/ui/dialog_component_preview/with_form.html.erb
    def with_form; end

    # Destructive confirmation using the prebuilt `shared/confirm_dialog` partial.
    # Renders spec/components/previews/ui/dialog_component_preview/confirm_destructive.html.erb
    def confirm_destructive; end

    # @!endgroup

    # @!group Reference

    # ## Don't — dialog without a title
    #
    # `title:` is required. It is wired to `aria-labelledby` on the `<dialog>` element,
    # giving screen-reader users the modal's accessible name when focus enters. Without it
    # the modal is announced without context. Always pass a descriptive `title:`.
    # @label Don't · no title (breaks aria-labelledby)
    def dont_no_title; end

    # @!endgroup
  end
end
