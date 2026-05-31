module AvatarHelper
  # xs/sm/md are below 44px WCAG 2.2 AAA touch target (24/32/40px) — use only
  # as decorative; wrap in a 44px+ interactive element if clickable.
  AVATAR_SIZES = {
    xs: { css: "w-6 h-6", px: 24, text: "text-xs" },
    sm: { css: "w-8 h-8", px: 32, text: "text-xs" },
    md: { css: "w-10 h-10", px: 40, text: "text-sm" },
    lg: { css: "w-16 h-16", px: 64, text: "text-lg" },
    xl: { css: "w-32 h-32", px: 128, text: "text-3xl" }
  }.freeze

  # Model-aware adapter: decides the avatar source (upload / gravatar / initials),
  # handles Active Storage variants, gravatar URLs, and the primary_color hue —
  # then renders the gem-maintained UI::AvatarComponent for presentation. The
  # component owns sizing, rounded-full, hue initials, and ARIA semantics.
  def avatar_for(user, size: :md, aria_label: nil)
    px = AVATAR_SIZES.fetch(size)[:px]

    case user.avatar_source
    when "upload"
      return render_initials_avatar(user, size, aria_label) unless user.avatar.attached?

      # main_app.url_for keeps the URL engine-context-safe (the shared header also
      # renders inside the markdowndocs engine layout, where AS routes aren't mounted).
      src = main_app.url_for(user.avatar.variant(resize_to_fill: [ px, px ]))
      render UI::AvatarComponent.new(src: src, size: size, aria_label: aria_label)
    when "gravatar"
      url = user.gravatar_url(size: px)
      return render_initials_avatar(user, size, aria_label) if url.nil?

      render UI::AvatarComponent.new(src: url, size: size, aria_label: aria_label, loading: "lazy")
    else
      render_initials_avatar(user, size, aria_label)
    end
  end

  private

  def render_initials_avatar(user, size, aria_label)
    custom_color = user.respond_to?(:primary_color) && user.primary_color.present? && user.primary_color != 210
    render UI::AvatarComponent.new(
      fallback: user.initials,
      size: size,
      hue: (custom_color ? user.primary_color : nil),
      aria_label: aria_label
    )
  end
end
