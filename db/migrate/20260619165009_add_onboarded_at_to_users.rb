class AddOnboardedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :onboarded_at, :datetime

    # Existing users predate onboarding — stamp them complete so the wizard
    # guard never retroactively traps them.
    User.reset_column_information
    User.update_all(onboarded_at: Time.current)
  end

  def down
    remove_column :users, :onboarded_at
  end
end
