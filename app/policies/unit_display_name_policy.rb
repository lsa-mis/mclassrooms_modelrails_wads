# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): UnitDisplayName (the
# department_group -> display_name override consumed wherever a unit's
# human-facing name renders, e.g. RoomSearch.unit_options) is admin-only
# reference-data configuration end to end, mirroring
# AnnouncementPolicy/EditorAssignmentPolicy — no editor carve-out, since this
# affects every unit's display name sitewide rather than a single editor's
# own unit.
class UnitDisplayNamePolicy < DirectoryPolicy
  def index?   = grant.admin?
  def new?     = grant.admin?
  def create?  = grant.admin?
  def edit?    = grant.admin?
  def update?  = grant.admin?
  def destroy? = grant.admin?
end
