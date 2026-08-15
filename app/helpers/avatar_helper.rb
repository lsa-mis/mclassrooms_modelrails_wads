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

  # Renders through the Identity read surface (PR 3 of the CTRL-1 arc) so the
  # source dispatch, gravatar availability rule, and hue default live in ONE
  # place — then hands presentation to the gem-maintained UI::AvatarComponent
  # (sizing, rounded-full, hue initials, ARIA semantics).
  def avatar_for(user, size: :md, aria_label: nil)
    identity = user.identity
    px = AVATAR_SIZES.fetch(size)[:px]

    case identity.source
    when "upload"
      return render_initials_avatar(identity, size, aria_label) unless identity.image?

      # main_app.url_for keeps the URL engine-context-safe (the shared header also
      # renders inside the markdowndocs engine layout, where AS routes aren't mounted).
      src = main_app.url_for(identity.image.variant(resize_to_fill: [ px, px ]))
      render UI::AvatarComponent.new(src: src, size: size, aria_label: aria_label)
    when "gravatar"
      # Identity#gravatar_url is consistency-gated: nil when "gravatar" left
      # available_sources (CheckGravatarJob flipped it off), so a stale source
      # renders initials instead of a permanently broken ?d=404 image.
      url = identity.gravatar_url(size: px)
      return render_initials_avatar(identity, size, aria_label) if url.nil?

      render UI::AvatarComponent.new(src: url, size: size, aria_label: aria_label, loading: "lazy")
    else
      render_initials_avatar(identity, size, aria_label)
    end
  end

  private

  def render_initials_avatar(identity, size, aria_label)
    custom_color = identity.primary_color.present? && identity.primary_color != Identity::DEFAULT_HUE
    render UI::AvatarComponent.new(
      fallback: identity.initials,
      size: size,
      hue: (custom_color ? identity.primary_color : nil),
      aria_label: aria_label
    )
  end
end
