class AddProjectRoleToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :invitations, :project_role, :string
  end
end
