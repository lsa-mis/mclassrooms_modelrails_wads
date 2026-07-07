# Single-tenant directory (spec D1): include in every root-level product
# controller (phases 3+). Requires authentication, then sets
# Current.workspace to the instance's one shared workspace — resolved from
# TenancyConfig rather than a `:workspace_slug`/`:slug` URL param, since
# product routes have no `/workspaces/:slug` nesting (see
# config/routes/app.rb). The template's slug-based WorkspaceScoped remains
# untouched and keeps serving /workspaces/:slug/... .
module DirectoryScoped
  extend ActiveSupport::Concern

  included do
    include Authenticatable
    before_action :set_directory_workspace
  end

  private

  # Mirrors WorkspaceScoped's redirect-with-flash convention for the locked/
  # missing edges (a 500 would be worse than a flash + redirect), but there
  # is no workspaces_path-equivalent index for a single-tenant directory, so
  # both edges land on root_path instead.
  def set_directory_workspace
    Current.workspace = Workspace.kept.find_by!(slug: TenancyConfig.shared_workspace_slug)
    redirect_to root_path, alert: t("workspaces.locked_notice") if Current.workspace.suspended?
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: t("workspaces.not_found")
  end
end
