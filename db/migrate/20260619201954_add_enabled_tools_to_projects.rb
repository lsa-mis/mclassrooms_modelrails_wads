class AddEnabledToolsToProjects < ActiveRecord::Migration[8.1]
  # Frozen (#449): migrations replay from zero on every fresh clone, so they
  # must never reference live app classes — a fork that renames Project or
  # reshapes ProjectTools::Registry breaks db:migrate on day one. The inline
  # model and the literal backfill value are this migration's world as of its
  # timestamp; they deliberately do not track the app.
  class MigrationProject < ActiveRecord::Base
    self.table_name = "projects"
  end

  def up
    add_column :projects, :enabled_tools, :json, null: false, default: []

    # Backfill existing projects with the tools that were default-enabled at
    # the time this migration shipped.
    MigrationProject.reset_column_information
    MigrationProject.update_all(enabled_tools: [ "docs" ])
  end

  def down
    remove_column :projects, :enabled_tools
  end
end
