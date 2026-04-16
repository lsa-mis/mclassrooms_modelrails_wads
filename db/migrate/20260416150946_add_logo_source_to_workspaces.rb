class AddLogoSourceToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :logo_source, :string, default: "initials", null: false
  end
end
