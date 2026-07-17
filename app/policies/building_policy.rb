# MiClassrooms Phase 5 Task 4 (Brief §14.1): re-parented onto DirectoryPolicy
# and widened past admin-only-everywhere (Phase 4 Task 8's original posture —
# see git history for the superseded `user.present? && RoleResolver...`
# predicates). Buildings/rooms follow a realty/Airbnb model: the building
# detail PAGE is viewer-visible on a visible building (mirrors RoomPolicy's
# #show? exactly — any current member sees a listed record; a hidden record
# is invisible to everyone but an admin); every MUTATING/admin-console
# affordance on that page (edit, hide/unhide, media/floor-plan management)
# stays admin-only and must be gated in the view. #index? stays admin-only:
# viewers reach a building only via a room's building card / breadcrumb nav,
# never a standalone building directory listing (Task 4 brief).
class BuildingPolicy < DirectoryPolicy
  # Viewer-visible listing (2026-07-17, Dave — supersedes Task 4's admin-only
  # index): any viewer-or-above browses the building directory, exactly like
  # RoomPolicy#index?. Non-admins see only LISTED buildings (Scope#resolve);
  # the admin-only "show hidden" toggle is gated by #view_inactive? below.
  def index? = grant.viewer?

  # Hidden buildings are invisible to non-admins (defense-in-depth backstop,
  # same reasoning as RoomPolicy#show?): an editor or plain viewer who hits
  # this URL directly is denied exactly like a signed-out visitor would be.
  # Building `in_feed` is warn-only per D6 (the listing Scope owns that
  # signal, see BuildingPolicy::Scope#resolve's `with_classrooms`) — unlike
  # RoomPolicy's `in_feed? && !hidden?`, a building's own visible_record?
  # checks ONLY `!hidden?`.
  def show? = grant.admin? || (grant.viewer? && visible_record?)

  def update? = grant.admin?
  def edit?   = update?

  def hide?   = grant.admin?
  def unhide? = grant.admin?

  # Gates the admin-only "show hidden buildings" toggle on the index (mirrors
  # RoomPolicy#view_inactive?). Not part of the §14.1 record action matrix —
  # it authorizes a controller-level view mode. BuildingsController#index only
  # widens Scope#resolve to hidden buildings when this is true.
  def view_inactive? = grant.admin?

  def manage_media?       = grant.admin?  # photo, floor-plan management
  def destroy_attachment? = grant.admin?

  # Buildings exist only via the nightly sync (Brief §5.3) — manual
  # creation/deletion is denied for everyone, admins included. Pinned
  # explicitly (mirrors RoomPolicy#create?/#destroy?) so this reads as a
  # deliberate rule, not an oversight.
  def create?  = false
  def destroy? = false

  private

  # A building is in-scope for a non-admin only while it isn't
  # curator-hidden. Deliberately NOT `record.in_feed? && !record.hidden?`
  # (RoomPolicy's rule) — building `in_feed` is warn-only per D6; the
  # listing Scope (`with_classrooms`) owns that signal, not the per-record
  # visibility check.
  def visible_record? = !record.hidden?

  class Scope < ApplicationPolicy::Scope
    # Safe default for every caller (mirrors RoomPolicy::Scope now that the
    # index is viewer-visible): LISTED classroom-containing buildings in the
    # current workspace. Non-admins never see curator-hidden buildings.
    # `for_current_workspace` is the defense-in-depth tenant backstop — Tenanted
    # models don't default_scope, so every Scope applies it explicitly.
    def resolve
      scope.for_current_workspace.with_classrooms.listed
    end

    # Admin-only expansion for the index's "show hidden" toggle. Belt-and-
    # suspenders against a crafted show_hidden param reaching this without a
    # #view_inactive? check: a non-admin (or signed-out) caller still gets
    # exactly #resolve's listed set, never the hidden buildings.
    def resolve_including_hidden
      return resolve unless user.present? && RoleResolver.for(user).admin?

      scope.for_current_workspace.with_classrooms
    end
  end
end
