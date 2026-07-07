# Phase 0 skeleton (MiClassrooms spec D5): the single role/scope abstraction
# every future Pundit policy consults. `admin?` and `viewer?` are real;
# `editor?` / `editor_unit_ids` are stubbed — always false / empty — because
# the EditorAssignment model doesn't exist until phase 5. `can_edit_room?`
# is therefore admin-only for now; once editor_unit_ids is populated, the
# non-admin branch below starts returning true for matching units without
# any change to this method's callers.
#
# `.for` is intentionally NOT memoized: every call re-reads the membership
# (and its role) fresh from the database, so a role change made between two
# calls is reflected immediately rather than served from a stale grant.
# Callers that need a single consistent grant across several checks should
# hold on to the returned Grant themselves rather than calling `.for` again.
class RoleResolver
  Grant = Data.define(:admin, :editor_unit_ids, :viewer) do
    def admin? = admin
    def viewer? = viewer
    def editor? = editor_unit_ids.any?

    def can_edit_room?(room)
      return true if admin?
      room.unit_id.present? && editor_unit_ids.include?(room.unit_id)
    end
  end

  # Matched on Role#slug — the stable identifier Role.system_default! keys
  # on (app/models/role.rb) and what TestLoginsController#grant_test_role
  # matches elsewhere — not Role#name, which is just the display label.
  ADMIN_ROLE_SLUGS = %w[owner admin].freeze

  def self.for(user)
    membership = TenancyConfig.shared_workspace&.memberships&.kept&.find_by(user:)

    Grant.new(
      admin: membership.present? && ADMIN_ROLE_SLUGS.include?(membership.role.slug),
      editor_unit_ids: [], # phase 5: EditorAssignment.where(user:).pluck(:unit_id)
      viewer: membership.present?
    )
  end
end
