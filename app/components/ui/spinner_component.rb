# frozen_string_literal: true

module UI
  # # Spinner
  #
  # An animated busy indicator for indeterminate waits. Carries `role="status"` and
  # an sr-only label so screen-reader users are told something is loading.
  #
  # ## Use when
  # - You need to signal an indeterminate, short-lived wait (a button submitting, a
  #   panel fetching). For determinate progress, use `progress` instead.
  #
  # ## Don't use when
  # - The wait is determinate (you know the percentage) — use `progress`.
  # - You strip the sr-only text — without it the spin is invisible to AT.
  #
  # ## Accessibility contract
  # - **Guarantees:** `role="status"` plus an sr-only loading label (i18n via
  #   `t` with an English default), so the spin is announced, not silent.
  # - **You supply:** nothing required; override the label via the
  #   `modelrails_ui.spinner.loading` locale key. (The spin is intentionally NOT
  #   motion-reduce-suppressed — a spinner with no motion conveys nothing.)
  class SpinnerComponent < ApplicationComponent
    BASE = "inline-block animate-spin rounded-full border-2 border-current border-t-transparent"

    SIZES = {
      sm: "size-4",
      default: "size-6",
      lg: "size-10"
    }.freeze

    def initialize(size: :default, **html_attrs)
      @size = size.to_sym
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:span,
        content_tag(:span, I18n.t("modelrails_ui.spinner.loading", default: "Loading…"), class: "sr-only"),
        class: cn(BASE, SIZES.fetch(@size, SIZES[:default]), @extra_class),
        role: "status",
        **@html_attrs)
    end
  end
end
