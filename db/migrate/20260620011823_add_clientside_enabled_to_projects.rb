class AddClientsideEnabledToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :clientside_enabled, :boolean, null: false, default: false
  end
end
