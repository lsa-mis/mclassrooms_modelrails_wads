# A silent no-op of this remove_column was observed once on an existing dev DB
# (columns persisted despite the migration recorded as "up"); it does not
# reproduce from a clean history on Rails 8.1.3 — the from-zero migrate path is
# now guarded by spec/migrations/fresh_database_migration_spec.rb, which proves
# these columns are gone and the result matches schema.rb. If it ever recurs on
# a long-lived DB: bin/rails db:schema:load from a clean state.
class RemoveResetPasswordFieldsFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :reset_password_token
    remove_column :users, :reset_password_token, :string
    remove_column :users, :reset_password_sent_at, :datetime
  end
end
