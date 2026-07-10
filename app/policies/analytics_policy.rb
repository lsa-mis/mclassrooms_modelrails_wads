# MiClassrooms Phase 5 Task 4 (Brief §14.1, interpretation 7): headless
# policy — there is no persisted Analytics model, so callers authorize
# against a bare `:analytics` symbol (`authorize :analytics, :show?`), same
# pattern as Admin::BulkUploadPolicy. Editors get READ-ONLY access (their own
# unit's usage numbers are the point of the dashboard); only admins can
# trigger a #refresh.
class AnalyticsPolicy < DirectoryPolicy
  def show?    = grant.admin? || grant.editor?
  def refresh? = grant.admin?
end
