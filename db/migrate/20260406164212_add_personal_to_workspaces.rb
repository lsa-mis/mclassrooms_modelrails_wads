class AddPersonalToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :personal, :boolean, default: false, null: false
  end
end
