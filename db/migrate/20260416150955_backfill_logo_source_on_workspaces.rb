class BackfillLogoSourceOnWorkspaces < ActiveRecord::Migration[8.1]
  # Pure SQL: referencing the Workspace model here couples the migration to the
  # app's future schema (its enums/validations) and breaks db:migrate from zero.
  def up
    execute <<~SQL
      UPDATE workspaces SET logo_source = 'upload'
      WHERE id IN (
        SELECT record_id FROM active_storage_attachments
        WHERE record_type = 'Workspace' AND name = 'logo'
      )
    SQL
  end

  def down
    # No-op: column default handles the reverse
  end
end
