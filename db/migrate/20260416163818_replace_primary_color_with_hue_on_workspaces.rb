class ReplacePrimaryColorWithHueOnWorkspaces < ActiveRecord::Migration[8.1]
  def change
    remove_column :workspaces, :primary_color, :string
    rename_column :workspaces, :primary_color_hue, :primary_color
  end
end
