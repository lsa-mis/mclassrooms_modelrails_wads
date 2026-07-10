# MiClassrooms Phase 5 Task 3 (Brief §14.1): base for the MiClassrooms
# product policies (RoomPolicy, and future BuildingPolicy/etc widening past
# admin-only). Directory policies consult RoleResolver exclusively for the
# §14.1 admin/editor/viewer matrix; the template's `can?`/membership helpers
# (ApplicationPolicy#can?/#membership) remain available for template
# surfaces (workspace settings, invitations, ...) that aren't part of this
# matrix.
class DirectoryPolicy < ApplicationPolicy
  private

  # Memoized per policy instance — RoleResolver.for(user) re-derives the
  # grant from the database on every call (by design, see
  # app/lib/role_resolver.rb), so callers that need a single consistent
  # grant across several predicate checks in the same request/example hold
  # onto this instance's memoized copy rather than re-resolving per call.
  def grant
    @grant ||= RoleResolver.for(user)
  end
end
