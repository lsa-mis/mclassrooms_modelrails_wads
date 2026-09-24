# frozen_string_literal: true

module UI
  # An ordered progress indicator: an `<ol>` of steps, each shown as complete, current, or pending.
  # Usage, options and the accessibility contract: docs/components/stepper.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class StepperComponent < ApplicationComponent
    ORIENTATIONS = %i[horizontal vertical].freeze
    STATUSES = %i[complete current pending].freeze

    # steps: [{ label:, description: (optional), status: :complete | :current | :pending }]
    def initialize(steps:, orientation: :horizontal, **html_attrs)
      @steps = steps
      @orientation = coerce_orientation(orientation.to_sym)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      wrapper_class = @orientation == :vertical \
        ? "flex flex-col gap-0" \
        : "flex items-start gap-0"

      content_tag(:ol, **list_attrs(wrapper_class)) do
        safe_join(@steps.each_with_index.map { |step, i| step_item(step, i) })
      end
    end

    private

    # Preflight strips the marker and Safari/VoiceOver drop the implicit list role
    # with it, so `role="list"` is load-bearing. Keys are stringified before the
    # caller's attrs merge: `content_tag` does not de-duplicate `:role` against
    # `"role"` — it emits both and lets the browser choose. That applied to the
    # default `aria-label` here too, which a caller could previously only
    # duplicate rather than replace.
    def list_attrs(wrapper_class)
      attrs = {
        "role" => "list",
        "class" => cn(wrapper_class, @extra_class),
        "aria-label" => I18n.t("modelrails_ui.stepper.progress", default: "Progress")
      }
      @html_attrs.each { |key, value| attrs[key.to_s] = value }
      attrs
    end

    def step_item(step, index)
      is_last = index == @steps.size - 1
      status  = coerce_status(step.fetch(:status, :pending).to_sym)

      if @orientation == :vertical
        vertical_item(step, status, is_last)
      else
        horizontal_item(step, status, is_last)
      end
    end

    def horizontal_item(step, status, is_last)
      content_tag(:li, class: "flex items-center #{is_last ? '' : 'flex-1'}") do
        concat step_circle(status, step[:label])
        concat content_tag(:p, step[:label], class: cn("ml-2 text-sm font-medium whitespace-nowrap", label_color(status))) unless step[:label].nil?
        concat connector(:horizontal, status) unless is_last
      end
    end

    def vertical_item(step, status, is_last)
      content_tag(:li, class: "relative flex gap-4") do
        concat content_tag(:div, class: "flex flex-col items-center") {
          concat step_circle(status, step[:label])
          concat connector(:vertical, status) unless is_last
        }
        concat content_tag(:div, class: "pb-6 pt-0.5 min-w-0") {
          concat content_tag(:p, step[:label], class: cn("text-sm font-medium", label_color(status)))
          concat content_tag(:p, step[:description], class: "mt-0.5 text-xs text-text-muted") if step[:description]
        }
      end
    end

    def step_circle(status, label)
      base = "flex size-8 shrink-0 items-center justify-center rounded-full text-xs font-semibold border-2"
      case status
      when :complete
        content_tag(:span, check_svg,
          class: cn(base, "border-interactive bg-interactive text-text-on-interactive"),
          role: "img",
          "aria-label": I18n.t("modelrails_ui.stepper.completed", default: "Completed"))
      when :current
        content_tag(:span, "●",
          class: cn(base, "border-interactive text-interactive"),
          "aria-current": "step")
      else
        content_tag(:span, "○",
          class: cn(base, "border-text-muted text-text-muted"),
          role: "img",
          "aria-label": I18n.t("modelrails_ui.stepper.pending", default: "Pending"))
      end
    end

    def connector(direction, status)
      filled = status == :complete
      if direction == :horizontal
        content_tag(:div, nil, class: cn("h-0.5 flex-1 mx-2", filled ? "bg-interactive" : "bg-border"))
      else
        content_tag(:div, nil, class: cn("w-0.5 flex-1 my-1", filled ? "bg-interactive" : "bg-border"))
      end
    end

    def label_color(status)
      case status
      when :complete then "text-text-heading"
      when :current  then "text-interactive"
      else "text-text-muted"
      end
    end

    def check_svg
      raw('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="20 6 9 17 4 12"/></svg>')
    end

    # Fail loud on an unknown orientation/status in development/test so misuse is
    # caught immediately; fall back to a safe default in production so a bad value
    # never 500s a page. The Rails.respond_to?(:env) guard stays correct even when
    # the Rails module is defined but Rails.env isn't booted (the gem's Rails-less
    # tests load rails/generators, which defines Rails without Rails.env).
    def coerce_orientation(orientation)
      return orientation if ORIENTATIONS.include?(orientation)

      fail_loud_or_default(orientation, ORIENTATIONS, "orientation", :horizontal)
    end

    def coerce_status(status)
      return status if STATUSES.include?(status)

      fail_loud_or_default(status, STATUSES, "status", :pending)
    end

    def fail_loud_or_default(value, allowed, name, fallback)
      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::StepperComponent: unknown #{name} #{value.inspect}. " \
          "Expected one of: #{allowed.join(", ")}."
      end

      fallback
    end
  end
end
