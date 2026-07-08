class AddEnabledToolsToProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :enabled_tools, :json, null: false, default: []

    # Backfill existing projects with the registry's default-enabled tools.
    # Project and ProjectTools::Registry were removed by a later migration
    # (DropExampleDomainTables, part of the fork's example-domain removal) —
    # inlining the historical default (:docs was the only default-enabled
    # tool) keeps this migration replayable against a fresh database instead
    # of depending on application constants that no longer exist.
    execute("UPDATE projects SET enabled_tools = '[\"docs\"]'")
  end

  def down
    remove_column :projects, :enabled_tools
  end
end
