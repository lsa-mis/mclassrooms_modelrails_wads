# MiClassrooms Phase 5 Task 4 (Brief §14.1): the admin console that grants/
# revokes editor claims on units is itself admin-only end to end — an editor
# managing their own (or anyone else's) editor assignments would be a
# privilege-escalation vector, so every action here consults only
# `grant.admin?`.
class EditorAssignmentPolicy < DirectoryPolicy
  def index?  = grant.admin?
  def new?    = grant.admin?
  def create? = grant.admin?
  def destroy? = grant.admin?
end
