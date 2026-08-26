class AddPersonalVisibilityCheckToActivityLogs < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :activity_logs,
      "visibility IN ('workspace','admin','personal')",
      name: "activity_logs_visibility_valid"
  end
end
