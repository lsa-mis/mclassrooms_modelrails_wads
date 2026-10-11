class SyncRunPolicy < DirectoryPolicy
  def index? = grant.admin? || grant.editor?
  def show?  = grant.admin? || grant.editor?
end
