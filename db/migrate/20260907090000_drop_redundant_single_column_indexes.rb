# frozen_string_literal: true

# Each index dropped here is a strict prefix of a composite that survives, so
# every read it served is served by the composite's leading column; all it
# still cost was a second B-tree write per INSERT/UPDATE (#691).
#
#   memberships (user_id)           ⊂ (user_id, last_accessed_at)
#                                   ⊂ (user_id, workspace_id) [unique]
#   projects (workspace_id)         ⊂ (workspace_id, slug) [unique]
#   resources (project_id)          ⊂ (project_id, position)
#   client_accesses (project_id)    ⊂ (project_id, user_id) [unique]
#   workspace_join_links (workspace_id) ⊂ (workspace_id, revoked_at)
#
# Deliberately NOT dropped: index_workspace_join_links_unique_active_per_workspace,
# also on (workspace_id) alone. Its `WHERE revoked_at IS NULL` makes it a
# constraint — at most one live join link per workspace — not a duplicate.
class DropRedundantSingleColumnIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :memberships, column: :user_id, name: "index_memberships_on_user_id"
    # Fork (MClassrooms): the Project domain and Clientside were removed, so
    # these three tables do not exist here; the guards keep the migration
    # replayable on a fresh clone without editing upstream's intent.
    remove_index :projects, column: :workspace_id, name: "index_projects_on_workspace_id" if table_exists?(:projects)
    remove_index :resources, column: :project_id, name: "index_resources_on_project_id" if table_exists?(:resources)
    remove_index :client_accesses, column: :project_id, name: "index_client_accesses_on_project_id" if table_exists?(:client_accesses)
    remove_index :workspace_join_links, column: :workspace_id, name: "index_workspace_join_links_on_workspace_id"
  end
end
