class BackfillPersonalWorkspaces < ActiveRecord::Migration[8.1]
  def up
    # Each user's first owned workspace is their personal workspace.
    # Find workspaces where the owner's first membership was created
    # at workspace creation time (personal workspaces are created in
    # the after_create callback).
    execute <<~SQL
      UPDATE workspaces
      SET personal = TRUE
      WHERE id IN (
        SELECT w.id
        FROM workspaces w
        INNER JOIN memberships m ON m.workspace_id = w.id
        INNER JOIN roles r ON r.id = m.role_id AND r.slug = 'owner'
        GROUP BY w.id
        HAVING COUNT(m.id) = 1
      )
      AND name LIKE '%''s Workspace'
    SQL
  end

  def down
    execute "UPDATE workspaces SET personal = FALSE"
  end
end
