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

  def avatar_for(user, size: :md, aria_label: nil)
    config = AVATAR_SIZES.fetch(size)

    case user.avatar_source
    when "upload"
      render_upload_avatar(user, config, aria_label)
    when "gravatar"
      render_gravatar_avatar(user, config, aria_label)
    else
      render_initials_avatar(user, config, aria_label)
    end
  end

  private

  def render_upload_avatar(user, config, aria_label)
    return render_initials_avatar(user, config, aria_label) unless user.avatar.attached?

    variant = user.avatar.variant(resize_to_fill: [ config[:px], config[:px] ])
    image_tag variant,
      class: "#{config[:css]} rounded-full object-cover",
      **avatar_aria_attrs(aria_label, alt: "")
  end

  def render_gravatar_avatar(user, config, aria_label)
    url = user.gravatar_url(size: config[:px])
    return render_initials_avatar(user, config, aria_label) if url.nil?

    image_tag url,
      class: "#{config[:css]} rounded-full object-cover",
      loading: "lazy",
      onerror: "this.style.display='none'",
      **avatar_aria_attrs(aria_label, alt: "")
  end

  def render_initials_avatar(user, config, aria_label)
    content_tag :span, user.initials,
      class: "#{config[:css]} #{config[:text]} rounded-full bg-interactive text-text-on-interactive
              flex items-center justify-center font-semibold",
      **avatar_aria_attrs(aria_label)
  end

  def avatar_aria_attrs(aria_label, alt: nil)
    if aria_label
      attrs = { role: "img", aria: { label: aria_label } }
      attrs[:alt] = aria_label if alt == ""
      attrs
    else
      attrs = { aria: { hidden: true } }
      attrs[:alt] = "" if alt == ""
      attrs
    end
  end
end
