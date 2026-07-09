# MiClassrooms Phase 3 Task 1 (spec D5, Brief §3.2): read-side authorization
# for the Find a Room screen. Every action here consults RoleResolver.for —
# never `role.permissions` directly — so the admin/editor matrix stays
# centralized in one place (app/lib/role_resolver.rb).
class RoomPolicy < ApplicationPolicy
  # DirectoryScoped already requires sign-in before any policy runs; these
  # just pin that browsing/viewing listed classrooms isn't further
  # role-gated. Room-detail (show) itself ships in phase 4 — this phase only
  # needs the predicate to exist for the index screen's link-through.
  def index? = user.present?
  def show? = user.present?

  # Rooms exist only via the nightly sync (Brief §5.3) — manual creation is
  # denied for everyone, admins included. Pinned explicitly (rather than
  # relying on ApplicationPolicy's default-false) so this reads as a
  # deliberate rule, not an oversight.
  def create? = false

  # Gates the admin-only "show hidden / not-in-feed rooms" toggle (Brief
  # §14.1). Editors do NOT get inactive views this phase — RoleResolver's
  # editor branch is still a phase-5 stub, so `admin?` is the only real
  # signal available.
  def view_inactive? = user.present? && RoleResolver.for(user).admin?

  class Scope < ApplicationPolicy::Scope
    # The safe default for every caller, admin included: listed classrooms
    # in the current workspace only. `for_current_workspace` is the
    # defense-in-depth backstop documented in
    # app/docs/developer/architecture.md — Tenanted models don't
    # default_scope, so every Scope must apply it explicitly.
    def resolve
      scope.for_current_workspace.classroom.listed
    end

    # Admin-only expansion for the inactive-rooms toggle. Belt-and-suspenders
    # against a crafted param or a controller bug that reaches this without
    # first checking `view_inactive?`: a non-admin (or signed-out) caller
    # still gets exactly #resolve's safe set, never the inactive rooms — and
    # even admins never get non-classroom rooms out of this scope.
    def resolve_including_inactive
      return resolve unless user.present? && RoleResolver.for(user).admin?
      scope.for_current_workspace.classroom
    end
  end
end
