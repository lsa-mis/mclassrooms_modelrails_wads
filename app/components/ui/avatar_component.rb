# frozen_string_literal: true

module UI
  class AvatarComponent < ApplicationComponent
    # Matches the host app's AvatarHelper presentation: AVATAR_SIZES, rounded-full,
    # and hue-tinted initials. The app's avatar_for helper keeps the model logic
    # (avatar_source / Active Storage / gravatar / primary_color) and renders this.
    SIZES = {
      xs: { css: "w-6 h-6",   text: "text-xs" },
      sm: { css: "w-8 h-8",   text: "text-xs" },
      md: { css: "w-10 h-10", text: "text-sm" },
      lg: { css: "w-16 h-16", text: "text-lg" },
      xl: { css: "w-32 h-32", text: "text-3xl" }
    }.freeze

    # src:        image URL (renders <img>); falls back to initials when nil
    # alt:        image alt text
    # fallback:   initials string (rendered as-is — caller supplies them)
    # size:       xs | sm | md | lg | xl
    # hue:        OKLCH hue integer for a custom initials background (else interactive)
    # aria_label: when set, exposes the avatar to AT; otherwise aria-hidden
    def initialize(src: nil, alt: "", fallback: nil, size: :md, hue: nil, aria_label: nil, **html_attrs)
      @src = src
      @alt = alt
      @fallback = fallback
      @size = size.to_sym
      @hue = hue
      @aria_label = aria_label
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      @src ? image_avatar : initials_avatar
    end

    private

    def config
      SIZES.fetch(coerce_size(@size))
    end

    # Fail loud on an unknown size in development/test so misuse is caught
    # immediately; fall back to :md in production so a bad size never 500s a page.
    # The Rails.respond_to?(:env) guard stays correct even when the Rails module is
    # defined but Rails.env isn't booted (the gem's Rails-less tests load
    # rails/generators, which defines Rails without Rails.env).
    def coerce_size(size)
      return size if SIZES.key?(size)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::AvatarComponent: unknown size #{size.inspect}. " \
          "Expected one of: #{SIZES.keys.join(", ")}."
      end

      :md
    end

    def image_avatar
      content_tag(:img, nil,
        src: @src, alt: (@aria_label.presence || @alt),
        class: cn(config[:css], "rounded-full object-cover", @extra_class),
        **aria_attrs, **@html_attrs)
    end

    def initials_avatar
      attrs = {
        class: cn(config[:css], config[:text],
          "rounded-full flex items-center justify-center font-semibold", color_classes, @extra_class)
      }.merge(aria_attrs).merge(@html_attrs)
      attrs[:style] = "--hue: #{@hue}" if @hue
      content_tag(:span, @fallback, **attrs)
    end

    def color_classes
      @hue ? "bg-hue-initials text-white" : "bg-interactive text-text-on-interactive"
    end

    def aria_attrs
      @aria_label ? { role: "img", "aria-label": @aria_label } : { "aria-hidden": "true" }
    end
  end
end
