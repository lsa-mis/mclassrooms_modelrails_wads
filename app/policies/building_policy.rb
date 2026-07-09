# MiClassrooms Phase 4 Task 8 (Brief §3.2, §14.1): the admin Buildings
# section is admin-only end to end — unlike RoomPolicy (where index?/show?
# are open to any signed-in viewer and only the inactive-views toggle is
# admin-gated), every action here consults RoleResolver.for(user).admin? —
# including index?/show? — because Buildings is an admin console, not a
# public-facing directory page. #edit?/#update? exist now (Task 9 wires the
# controller actions) so the policy denial is provable end to end before the
# controller actions exist — see BuildingsController's `before_action
# :set_building, only: [:show]` comment for why the routes/policy can be
# ahead of the controller without raising.
class BuildingPolicy < ApplicationPolicy
  def index?  = user.present? && RoleResolver.for(user).admin?
  def show?   = user.present? && RoleResolver.for(user).admin?
  def edit?   = user.present? && RoleResolver.for(user).admin?
  def update? = edit?

  # Buildings arrive only via the nightly sync (mirrors RoomPolicy#create? —
  # manual creation is denied for everyone, admins included).
  def create? = false

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
