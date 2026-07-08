class DropDeadExampleDomainColumns < ActiveRecord::Migration[8.1]
  def up
    remove_column :workspaces, :max_projects
    remove_column :invitations, :company_name
    remove_column :invitations, :project_role
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
