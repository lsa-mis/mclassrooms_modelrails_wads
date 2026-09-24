# frozen_string_literal: true

module UI
  # A single message bubble for a chat or comment transcript.
  # Usage, options and the accessibility contract: docs/components/chat_bubble.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class ChatBubbleComponent < ApplicationComponent
    BUBBLE_BASE = "max-w-[80%] rounded-2xl px-4 py-2 text-sm leading-relaxed"

    # Sent uses a SOLID interactive fill with adaptive on-color (white in light, dark
    # in dark) — AAA. Received uses the sunken surface with body text — AAA. Body copy
    # is text-text-body, never text-text-heading (heading token is for headings).
    VARIANTS = {
      sent:     "bg-interactive text-text-on-interactive rounded-br-none",
      received: "bg-surface-sunken text-text-body rounded-bl-none"
    }.freeze

    ALIGN = {
      sent:     "flex-row-reverse",
      received: "flex-row"
    }.freeze

    META_BASE = "mt-1 flex items-baseline gap-2 text-xs text-text-muted"

    # sent:      true for outgoing messages, false for incoming (default).
    # author:    optional speaker name, shown above the bubble. When omitted, an
    #            sr-only direction label still makes the speaker perceivable.
    # timestamp: optional time string rendered with the meta line.
    # avatar:    optional URL for a small decorative avatar (received messages only).
    def initialize(sent: false, author: nil, timestamp: nil, avatar: nil, **html_attrs)
      @variant     = coerce_variant(sent)
      @author      = author
      @timestamp   = timestamp
      @avatar      = avatar
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      wrapper_cls = cn("flex items-end gap-2", ALIGN.fetch(@variant), @extra_class)

      content_tag(:div, class: wrapper_cls, **@html_attrs) do
        concat avatar_img if @avatar && @variant == :received
        concat bubble_block
      end
    end

    private

    # Decorative — the speaker is conveyed by text (author/sr-only label), so the
    # avatar adds nothing for AT and carries empty alt + aria-hidden.
    def avatar_img
      content_tag(:img, nil,
        src: @avatar,
        alt: "",
        class: "size-7 rounded-full object-cover shrink-0",
        "aria-hidden": "true")
    end

    def bubble_block
      content_tag(:div, class: cn("flex flex-col", @variant == :sent ? "items-end" : "items-start")) do
        concat speaker_label
        concat content_tag(:div, content, class: cn(BUBBLE_BASE, VARIANTS.fetch(@variant)))
        concat meta_line if @author || @timestamp
      end
    end

    # The speaker is NEVER conveyed by alignment/color alone. A named author is shown
    # visibly in the meta line; the direction (you vs them) is always announced via an
    # sr-only label so an SR user knows who spoke regardless of visual side.
    def speaker_label
      content_tag(:span, direction_label, class: "sr-only")
    end

    def meta_line
      content_tag(:p, class: META_BASE) do
        concat content_tag(:span, @author) if @author
        concat content_tag(:span, @timestamp) if @timestamp
      end
    end

    def direction_label
      key = @variant == :sent ? "sent" : "received"
      default = @variant == :sent ? "You said" : "They said"
      I18n.t("modelrails_ui.chat_bubble.#{key}", default: default)
    end

    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :received in production so a bad value never 500s a
    # page. `sent:` is the boolean public API — true→:sent, false→:received — but a
    # caller passing anything else (e.g. a stray string) is a real bug, not a third
    # variant. The Rails.respond_to?(:env) guard stays correct even when Rails is
    # defined but not booted (the gem's Rails-less render tests).
    def coerce_variant(sent)
      return :sent if sent == true
      return :received if sent == false || sent.nil?

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::ChatBubbleComponent: unknown sent value #{sent.inspect}. " \
          "Expected true (sent) or false (received)."
      end

      :received
    end
  end
end
