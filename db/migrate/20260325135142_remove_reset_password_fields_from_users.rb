# KNOWN ISSUE: This migration silently no-ops when run via `bin/rails db:migrate`
# on SQLite 3.51+ with Rails 8.1. The columns remain in the DB despite the migration
# being recorded as "up" in schema_migrations. Running the migration class directly
# via `rails runner` works correctly. The root cause is under investigation — appears
# to be a Rails/SQLite interaction with transactional DDL and remove_column.
#
# Workaround: if columns persist after migrate, run `bin/rails db:schema:load` from
# a clean state, or execute the removal manually via rails runner.
class RemoveResetPasswordFieldsFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :reset_password_token
    remove_column :users, :reset_password_token, :string
    remove_column :users, :reset_password_sent_at, :datetime
  end
end
