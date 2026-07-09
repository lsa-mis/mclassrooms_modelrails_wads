# MiClassrooms Phase 4 Task 11 (Brief §5.3, §14.1): headless policy for the
# admin bulk-upload flow — there is no persisted BulkUpload model (see
# config/routes/app.rb's `resources :bulk_uploads, only: [:new, :create]`
# comment), so `authorize` is called against a bare `:bulk_upload` symbol
# with `policy_class: Admin::BulkUploadPolicy` (same pattern as
# Settings::AvatarPolicy/Settings::ProfilePolicy — a real, non-namespaced
# `authorize` target would resolve Pundit's naming convention to the
# unqualified `BulkUploadPolicy`, not this namespaced class). Admin-only end
# to end, mirroring BuildingPolicy's all-admin posture: this whole section is
# an admin console action, not a public-facing directory page.
class Admin::BulkUploadPolicy < ApplicationPolicy
  def new?    = user.present? && RoleResolver.for(user).admin?
  def create? = new?
end
