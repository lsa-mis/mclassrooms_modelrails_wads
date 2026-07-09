# frozen_string_literal: true

# Single role/scope abstraction (spec D5, Brief §14.1). Resolves a user's
# effective grant — admin / editor / viewer — from the DATABASE on every
# call; never session-cached (fixes Brief §11.1). Policies consult only this
# object for the §14.1 capability matrix. Swapping the assignment source
# later (e.g. an OktaClaimsResolver) touches only this file.
#
# `RoleResolver` is itself the grant: `.for(user)` builds a fresh instance
# rather than returning a separate Grant value, so a role change made
# between two calls is reflected immediately rather than served stale.
# Callers that need a single consistent grant across several checks should
# hold on to the returned instance themselves rather than calling `.for`
# again.
class RoleResolver
  # Matched on Role#slug — the stable identifier Role.system_default! keys
  # on (app/models/role.rb) and what TestLoginsController#grant_test_role
  # matches elsewhere — not Role#name, which is just the display label.
  ADMIN_ROLE_SLUGS = %w[owner admin].freeze

  def self.for(user)
    new(user)
  end

  def initialize(user)
    # Prefer the request-resolved Current.workspace (set by DirectoryScoped/
    # WorkspaceScoped) so this doesn't re-derive tenancy when a controller
    # already has. Fall back to TenancyConfig.shared_workspace for callers
    # that run before any workspace-scoping concern sets Current.workspace —
    # e.g. PagesController#home's admin check on the unauthenticated-access
    # marketing page, which has no DirectoryScoped before_action to resolve
    # it first. Both resolve to the same single shared workspace (D1).
    workspace = Current.workspace || TenancyConfig.shared_workspace
    membership = user && workspace&.memberships&.kept&.find_by(user: user)
    @admin = ADMIN_ROLE_SLUGS.include?(membership&.role&.slug)
    @viewer = membership.present?
    # A discarded (revoked) membership nullifies editor grants: default-deny.
    @editor_unit_ids = @viewer ? EditorAssignment.where(user: user).pluck(:unit_id) : []
  end

  attr_reader :editor_unit_ids

  def admin? = @admin
  def viewer? = @viewer
  def editor? = @editor_unit_ids.any?

  # Brief §14.1: blank/unknown department group => admin-only.
  # No unit means no editor claim.
  def can_edit_room?(room)
    return true if admin?
    return false if room.unit_id.nil?
    editor_unit_ids.include?(room.unit_id)
  end
end
