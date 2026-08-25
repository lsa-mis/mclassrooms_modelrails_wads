module WorkspaceIconHelper
  # The fallback chain (logo → owner's uploaded avatar → initials) lives in
  # WorkspaceIcon (#654); this helper only supplies route context and renders.
  def workspace_icon_for(workspace, size: :md)
    args = WorkspaceIcon.new(workspace, size: size)
                        .avatar_args { |variant| main_app.url_for(variant) }
    render UI::AvatarComponent.new(**args)
  end
end
