class RenameMaxTeamsToMaxProjects < ActiveRecord::Migration[8.1]
  def change
    rename_column :workspaces, :max_teams, :max_projects
  end
end
