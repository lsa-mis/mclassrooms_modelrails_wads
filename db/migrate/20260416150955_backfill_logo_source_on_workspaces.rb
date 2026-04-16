class BackfillLogoSourceOnWorkspaces < ActiveRecord::Migration[8.1]
  def up
    Workspace.joins(:logo_attachment).update_all(logo_source: "upload")
  end

  def down
    # No-op: column default handles the reverse
  end
end
