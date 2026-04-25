class RemovePrimaryColorFromProjects < ActiveRecord::Migration[8.1]
  def change
    remove_column :projects, :primary_color, :string
  end
end
