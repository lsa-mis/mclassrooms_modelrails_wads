# MiClassrooms Phase 5 Task 4 (Brief §14.1, interpretation 7): the nightly
# sync-run history/status is read-only for editors (same reasoning as
# AnalyticsPolicy — visibility into pipeline health without the ability to
# act on it); only admins can resume a failed run or trigger a manual
# refresh.
class SyncRunPolicy < DirectoryPolicy
  def index? = grant.admin? || grant.editor?
  def show?  = grant.admin? || grant.editor?

  def resume?  = grant.admin?
  def refresh? = grant.admin?
end
