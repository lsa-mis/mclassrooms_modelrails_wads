# MiClassrooms Phase 5 Task 3 (Brief §14.1): the full admin/editor/viewer
# capability matrix for rooms, driven entirely by RoleResolver (via
# DirectoryPolicy#grant) — never `role.permissions` directly, so the matrix
# stays centralized in one place (app/lib/role_resolver.rb). Supersedes the
# phase-3/4 viewer-only index?/show? and admin-only edit?/update? — see
# git history for the superseded predicates.
class RoomPolicy < DirectoryPolicy
  # Brief §14.1: any viewer-or-above (i.e. any current member) can browse the
  # directory; a signed-in user with no membership at all gets no directory
  # access. Under the shared-workspace onboarding posture every signed-in
  # user auto-joins with a membership, so this only bites a caller with a
  # revoked/discarded membership.
  def index? = grant.viewer?

  # Hidden / out-of-feed rooms are invisible to non-admins EVERYWHERE,
  # including direct URLs (Brief §3.2, §8 rule 5) — editors included: an
  # editor who hides a room loses sight of it (Brief §14.1 one-way hide).
  # This is defense-in-depth: RoomsController's redirect_inactive_for_non_admins
  # before_action already gives non-admins a friendly redirect for the common
  # case (GET /rooms/:id, /rooms/:id/floor_plan) before #authorize ever runs;
  # this predicate is the backstop for any path that reaches #authorize
  # directly.
  def show? = grant.admin? || (grant.viewer? && visible_record?)
  def floor_plan? = show?

  # Curated fields only (nickname, ada_seat_count, ...); media is
  # manage_media?, admin-only even for editors. An editor can only edit a
  # room that is BOTH in their assigned unit AND currently visible — hiding
  # a room (even one's own unit's) removes editing access along with
  # visibility, matching #show?'s reasoning above.
  def update? = grant.admin? || (grant.can_edit_room?(record) && visible_record?)
  def edit? = update?

  def hide?   = grant.admin? || (grant.can_edit_room?(record) && visible_record?)
  def unhide? = grant.admin?            # one-way for editors (Brief §14.1)

  def manage_media?       = grant.admin?  # photos, galleries, panoramas, charts, floor plans
  def destroy_attachment? = grant.admin?

  # Rooms exist only via the nightly sync (Brief §5.3) — manual creation/
  # deletion is denied for everyone, admins included. Pinned explicitly
  # (rather than relying on ApplicationPolicy's default-false) so this reads
  # as a deliberate rule, not an oversight.
  def create?  = false
  def destroy? = false

  # Gates the admin-only "show hidden / not-in-feed rooms" toggle (Brief
  # §14.1). Not itself part of the §14.1 action matrix (it authorizes a
  # controller-level view mode, not an action on a room record), but
  # required by RoomsController#base_scope's `authorize Room, :view_inactive?`
  # for the inactive-rooms/inactive-buildings views. Editors do NOT get
  # inactive views — RoleResolver's admin? is the only signal that grants
  # this, consistent with every other admin-only predicate above.
  def view_inactive? = grant.admin?

  private

  # A room is in-scope for a non-admin only while it's both synced into the
  # feed and not curator-hidden — the same "listed" definition Room::listed
  # encodes at the query layer, checked here at the record layer for a
  # single already-loaded room.
  def visible_record? = record.in_feed? && !record.hidden?

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
