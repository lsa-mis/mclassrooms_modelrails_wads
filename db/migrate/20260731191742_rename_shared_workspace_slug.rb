# PR #61 renamed the shared-workspace slug in config (miclassrooms -> mclassrooms)
# but never migrated existing rows. Any environment whose shared workspace predates
# that rename resolves TenancyConfig.shared_workspace_slug to a slug no record has,
# so DirectoryScoped#set_directory_workspace's `Workspace.kept.find_by!` raises and
# every product page redirects with "Workspace not found." This aligns the row.
#
# Idempotent + collision-safe: no-op when the new slug already exists (already
# aligned, or a freshly-seeded env) and when the old slug is absent. Uses a
# migration-local model + update_all so no slug-generation callback or validation
# on the app's Workspace can interfere. Slugs are hardcoded so this stays a fixed
# historical fact — a future slug rename gets its own migration, not a re-run of
# this one against whatever TenancyConfig happens to return then.
class RenameSharedWorkspaceSlug < ActiveRecord::Migration[8.1]
  OLD_SLUG = "miclassrooms"
  NEW_SLUG = "mclassrooms"

  class MigrationWorkspace < ActiveRecord::Base
    self.table_name = "workspaces"
  end

  def up
    return if MigrationWorkspace.exists?(slug: NEW_SLUG)

    MigrationWorkspace.where(slug: OLD_SLUG).update_all(slug: NEW_SLUG)
  end

  def down
    return if MigrationWorkspace.exists?(slug: OLD_SLUG)

    MigrationWorkspace.where(slug: NEW_SLUG).update_all(slug: OLD_SLUG)
  end
end
