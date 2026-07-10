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
  # Admin-only listing — mirrors the deliberate absence of a viewer-facing
  # building index anywhere in the app (Task 4 brief: "viewers reach
  # buildings via room→building nav, NOT a viewer building index").
  def index? = grant.admin?

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
    # Admin-only page: the "safe" scope and the "admin" scope are the same
    # set (every classroom-containing building in the workspace, listed or
    # hidden alike is still gated behind #index? itself) — unlike
    # RoomPolicy::Scope there is no narrower default for a non-admin caller,
    # because a non-admin never reaches this Scope at all (BuildingPolicy
    # denies #index? before the controller ever resolves it). Kept as a real
    # Scope class (rather than inlining `Building.for_current_workspace...`
    # in the controller) so a future caller has one canonical place to widen
    # or narrow this, per the brief's "Scope too OR the controller scopes
    # explicitly" guidance — BuildingsController#index composes the
    # show_hidden/search variations on top of #resolve here.
    def resolve
      scope.for_current_workspace.with_classrooms
    end
  end
end
