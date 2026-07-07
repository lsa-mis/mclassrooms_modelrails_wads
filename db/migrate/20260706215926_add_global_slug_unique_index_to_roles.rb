class AddGlobalSlugUniqueIndexToRoles < ActiveRecord::Migration[8.1]
  # The composite unique index on (workspace_id, slug) treats NULL as distinct
  # (SQLite, Postgres, and MySQL alike), so global roles — workspace_id IS NULL —
  # had no database-level uniqueness. Request-time find_or_create_by! of global
  # roles was race-safe only via SQLite's single-writer serialization; on a
  # Postgres/MySQL fork, concurrent first-boot signups could insert duplicates.
  def change
    add_index :roles, :slug,
      unique: true,
      where: "workspace_id IS NULL",
      name: "index_roles_on_slug_where_global"
  end
end
