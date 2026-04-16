class AddPrimaryColorHueToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :primary_color_hue, :integer, default: 210
  end
end
