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

  # Renders through the Identity read surface: the helper asks ONE question —
  # Identity#image_url, where the case-on-source lives (#653) — and hands
  # presentation to the gem-maintained UI::AvatarComponent. nil URL means
  # initials.
  def avatar_for(user, size: :md, aria_label: nil)
    identity = user.identity
    px = AVATAR_SIZES.fetch(size)[:px]

    # main_app.url_for keeps upload variant URLs engine-context-safe (the
    # shared header also renders inside the markdowndocs engine layout, where
    # AS routes aren't mounted).
    url = identity.image_url(size: px) { |variant| main_app.url_for(variant) }
    return render_initials_avatar(identity, size, aria_label) unless url

    # fallback: arms the component's broken-image recovery (#756) — a 404ing
    # image swaps to initials instead of the browser glyph.
    render UI::AvatarComponent.new(
      src: url, fallback: identity.initials, hue: identity.custom_hue,
      size: size, aria_label: aria_label,
      loading: ("lazy" if identity.remote_image?)
    )
  end

  private

  def render_initials_avatar(identity, size, aria_label)
    render UI::AvatarComponent.new(
      fallback: identity.initials,
      size: size,
      hue: identity.custom_hue,
      aria_label: aria_label
    )
  end
end
