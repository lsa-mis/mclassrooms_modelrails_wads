# Sync history is read-only for a workspace's admins and editors; retrying or starting a sync is
# an operator action (Operations::SyncRunPolicy).
class SyncRunPolicy < DirectoryPolicy
  def index? = grant.admin? || grant.editor?
  def show?  = grant.admin? || grant.editor?
end
