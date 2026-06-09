# frozen_string_literal: true

module UI
  # # Alert
  #
  # An inline contextual message banner — NOT the flash/toast pipeline. Renders a
  # `<div>` live region with semantics matched to its urgency and an AAA-tuned color
  # treatment.
  #
  # ## Use when
  # - You need an inline, in-page message tied to surrounding content: a form-level
  #   error summary, a destructive-action warning, an empty-state notice.
  #
  # ## Don't use when
  # - It's an ephemeral flash/notice — that's the app's toast system (`shared/_toasts`).
  #
  # ## Accessibility contract
  # - **Guarantees:** a live region matched to urgency — `role="status"`/`aria-live="polite"`
  #   for the neutral tone (and `info`/`success`/`warning`), `role="alert"`/
  #   `aria-live="assertive"` for `danger` — and AAA-contrast text on the banner surface.
  # - **You supply:** a title and/or description (kwargs or the `alert_title` /
  #   `alert_description` slots) and a valid `tone` (an unknown one raises in development).
  #
  # ## Tone
  # An alert is always a filled banner — it has no shape axis, only a tone:
  # `neutral` · `info` · `success` · `warning` · `danger`
  # (`variant:` is accepted as a deprecated alias for `tone:` — `default`→`neutral`,
  # `destructive`→`danger`, the rest 1:1.)
  class AlertComponent < ApplicationComponent
    OUTER_CLASSES = "relative grid w-full grid-cols-[0_1fr] items-start gap-y-0.5 rounded-lg border " \
                    "px-4 py-3 text-sm has-[>svg]:grid-cols-[calc(var(--spacing)*4)_1fr] " \
                    "has-[>svg]:gap-x-3 [&>svg]:size-4 [&>svg]:translate-y-0.5 [&>svg]:text-current"

    # Signal levels share the tinted-surface treatment used by the toast cards
    # (`bg-<level>-surface` + `border-<level>-border` + `text-<level>`), so an alert
    # reads its severity the same way a toast does. `text-<level>` (no `/90` opacity
    # modifier — that would lower contrast below the AAA 7:1 floor on the description).
    VARIANTS = {
      neutral: "bg-surface-raised text-text-body",
      info:    "bg-info-surface border-info-border text-info [&>svg]:text-current *:data-[slot=alert-description]:text-info",
      success: "bg-success-surface border-success-border text-success [&>svg]:text-current *:data-[slot=alert-description]:text-success",
      warning: "bg-warning-surface border-warning-border text-warning [&>svg]:text-current *:data-[slot=alert-description]:text-warning",
      danger:  "bg-danger-surface border-danger-border text-danger [&>svg]:text-current *:data-[slot=alert-description]:text-danger"
    }.freeze

    # Deprecated `variant:` alias → `tone:`. The old flat `variant` enum maps 1:1 onto
    # tone except `default`→`neutral` and `destructive`→`danger`. Resolved in coerce_tone.
    VARIANT_ALIASES = { default: :neutral, destructive: :danger }.freeze

    # Live-region semantics by urgency: only `danger` is urgent (assertive); the
    # neutral tone and info/success/warning announce politely.
    ROLES = { neutral: "status", info: "status", success: "status", warning: "status", danger: "alert" }.freeze
    LIVE  = { neutral: "polite", info: "polite", success: "polite", warning: "polite", danger: "assertive" }.freeze

    renders_one :alert_title, "UI::AlertComponent::TitleComponent"
    renders_one :alert_description, "UI::AlertComponent::DescriptionComponent"

    # title: and description: are kwarg shorthands for plain-text content.
    # Use slots (with_alert_title / with_alert_description) for rich HTML.
    # Slots take precedence over kwargs when both are provided.
    def initialize(tone: :neutral, variant: nil, title: nil, description: nil, **html_attrs)
      @tone = coerce_tone(tone, variant)
      @title = title
      @description = description
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, safe_join([ resolved_title, resolved_description ].compact),
        **@html_attrs,
        role: ROLES.fetch(@tone),
        "aria-live": LIVE.fetch(@tone),
        class: cn(OUTER_CLASSES, VARIANTS.fetch(@tone), @extra_class))
    end

    class TitleComponent < ApplicationComponent
      CLASSES = "col-start-2 line-clamp-1 min-h-4 font-medium tracking-tight"

      def call
        content_tag(:h5, content, class: CLASSES)
      end
    end

    class DescriptionComponent < ApplicationComponent
      CLASSES = "col-start-2 grid justify-items-start gap-1 text-sm text-text-muted [&_p]:leading-relaxed"

      def call
        content_tag(:div, content, class: CLASSES, data: { slot: "alert-description" })
      end
    end

    private

    # Resolve the tone, accepting the deprecated `variant:` alias. When `variant:` is
    # passed (non-nil) it wins (legacy call sites) and is mapped onto a tone via
    # VARIANT_ALIASES (default→neutral, destructive→danger, the rest 1:1); otherwise
    # the new `tone:` axis is used.
    #
    # Fail loud on an unknown tone in development/test so misuse is caught immediately;
    # fall back to :neutral in production so a bad tone never 500s a page. The
    # Rails.respond_to?(:env) guard stays correct even when the Rails module is defined
    # but Rails.env isn't booted (the gem's Rails-less tests load rails/generators,
    # which defines Rails without Rails.env).
    def coerce_tone(tone, variant)
      tone = variant.nil? ? tone.to_sym : VARIANT_ALIASES.fetch(variant.to_sym, variant.to_sym)
      return tone if VARIANTS.key?(tone)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::AlertComponent: unknown tone #{tone.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")} " \
          "(deprecated variant: alias — default→neutral, destructive→danger)."
      end

      :neutral
    end

    def resolved_title
      alert_title || (@title && content_tag(:h5, @title, class: TitleComponent::CLASSES))
    end

    def resolved_description
      return alert_description if alert_description

      @description && content_tag(:div, @description,
        class: DescriptionComponent::CLASSES,
        data: { slot: "alert-description" })
    end
  end
end
