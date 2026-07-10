# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): SyncScopeRule (the
# campus_allow/building_allow/building_exclude rows that scope which rooms
# the next sync run pulls in) is admin-only reference-data configuration end
# to end, mirroring AnnouncementPolicy/EditorAssignmentPolicy — no editor
# carve-out, since a sync-scope change affects the entire directory's next
# sync, not a single editor's own unit.
class SyncScopeRulePolicy < DirectoryPolicy
  def index?   = grant.admin?
  def new?     = grant.admin?
  def create?  = grant.admin?
  def edit?    = grant.admin?
  def update?  = grant.admin?
  def destroy? = grant.admin?
end
