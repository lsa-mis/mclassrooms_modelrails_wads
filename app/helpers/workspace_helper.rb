module WorkspaceHelper
  WORKSPACE_ICON_SIZES = {
    sm: { css: "w-8 h-8", px: 32, text: "text-xs" },
    md: { css: "w-10 h-10", px: 40, text: "text-sm" },
    lg: { css: "w-16 h-16", px: 64, text: "text-xl" }
  }.freeze

  def workspace_icon_for(workspace, size: :md)
    config = WORKSPACE_ICON_SIZES.fetch(size)

    if workspace.logo.attached?
      render_workspace_logo(workspace, config)
    elsif workspace.personal? && workspace.owner&.avatar&.attached? && workspace.owner.avatar_source == "upload"
      render_owner_avatar_fallback(workspace, config)
    else
      render_workspace_initials(workspace, config)
    end
  end

  private

  def render_workspace_logo(workspace, config)
    variant = workspace.logo.variant(resize_to_fill: [ config[:px], config[:px] ])
    # main_app.url_for is required because the shared header / workspace
    # switcher render inside the markdowndocs engine layout too — and
    # `image_tag variant` from a non-main-app context fails (Active Storage
    # routes live on main_app, not engine routers). See avatar_helper for
    # the same fix; same pattern, same reason.
    image_tag main_app.url_for(variant),
      class: "#{config[:css]} rounded-full object-cover",
      alt: workspace.name,
      aria: { hidden: true }
  end

  def render_owner_avatar_fallback(workspace, config)
    avatar_for(workspace.owner, size: WORKSPACE_ICON_SIZES.key(config))
  end

  def render_workspace_initials(workspace, config)
    hue = workspace.primary_color || 210

    content_tag :div, workspace.initials,
      class: "#{config[:css]} #{config[:text]} rounded-full flex items-center justify-center
              font-semibold text-white bg-hue-initials",
      style: "--hue: #{hue}",
      aria: { hidden: true }
  end
end
