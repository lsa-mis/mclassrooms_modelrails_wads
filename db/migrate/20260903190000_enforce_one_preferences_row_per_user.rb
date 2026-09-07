# frozen_string_literal: true

# #884: user_preferences had a plain index on user_id, so a race between two
# lazy creators (the sign-in timezone beacon and any settings write) could
# leave a user with two rows, and has_one returned whichever it met first.
# Collapse existing duplicates to the most recently updated row, then make
# the index unique so the database refuses a second one.
class EnforceOnePreferencesRowPerUser < ActiveRecord::Migration[8.1]
  class RawPreferences < ActiveRecord::Base
    self.table_name = "user_preferences"
  end

  def up
    RawPreferences.group(:user_id).having("COUNT(*) > 1").pluck(:user_id).each do |user_id|
      keep = RawPreferences.where(user_id: user_id).order(updated_at: :desc, id: :desc).first
      RawPreferences.where(user_id: user_id).where.not(id: keep.id).delete_all
    end

    remove_index :user_preferences, name: "index_user_preferences_on_user_id"
    add_index :user_preferences, :user_id, unique: true, name: "index_user_preferences_on_user_id"
  end

  def down
    remove_index :user_preferences, name: "index_user_preferences_on_user_id"
    add_index :user_preferences, :user_id, name: "index_user_preferences_on_user_id"
  end
end
