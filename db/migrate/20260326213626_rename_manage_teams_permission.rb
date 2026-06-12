class RenameManageTeamsPermission < ActiveRecord::Migration[8.1]
  # Inline stub instead of the app model so this migration can't break when
  # Role later gains enums/validations on columns that don't exist at this
  # point in history. The JSON column type comes from the database, so
  # permissions (de)serialization works without the real class.
  class Role < ActiveRecord::Base
    self.table_name = "roles"
  end

  def up
    Role.where("permissions LIKE '%manage_teams%'").find_each do |role|
      perms = role.permissions.dup
      perms["manage_projects"] = perms.delete("manage_teams") if perms.key?("manage_teams")
      role.update_column(:permissions, perms)
    end
  end

  def down
    Role.where("permissions LIKE '%manage_projects%'").find_each do |role|
      perms = role.permissions.dup
      perms["manage_teams"] = perms.delete("manage_projects") if perms.key?("manage_projects")
      role.update_column(:permissions, perms)
    end
  end
end
