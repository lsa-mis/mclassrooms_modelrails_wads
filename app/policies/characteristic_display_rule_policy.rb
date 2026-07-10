# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): CharacteristicDisplayRule
# (the icon/category-override/filterable/team-learning overrides keyed to a
# characteristic's normalized short_code) is admin-only reference-data
# configuration end to end — it drives how EVERY room's characteristics
# render/filter sitewide, not a single unit's curated content, so there is no
# editor carve-out, mirroring AnnouncementPolicy/EditorAssignmentPolicy.
class CharacteristicDisplayRulePolicy < DirectoryPolicy
  def index?   = grant.admin?
  def new?     = grant.admin?
  def create?  = grant.admin?
  def edit?    = grant.admin?
  def update?  = grant.admin?
  def destroy? = grant.admin?
end
