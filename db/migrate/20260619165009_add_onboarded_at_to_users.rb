class AddOnboardedAtToUsers < ActiveRecord::Migration[8.1]
  # Frozen (#449): migrations replay from zero on every fresh clone, so they
  # must never reference live app classes — a fork that reshapes User (or a
  # future User callback/validation) must not be able to break db:migrate.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    add_column :users, :onboarded_at, :datetime

    # Existing users predate onboarding — stamp them complete so the wizard
    # guard never retroactively traps them.
    MigrationUser.reset_column_information
    MigrationUser.update_all(onboarded_at: Time.current)
  end

  def down
    remove_column :users, :onboarded_at
  end
end
