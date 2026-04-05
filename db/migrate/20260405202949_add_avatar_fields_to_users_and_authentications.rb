class AddAvatarFieldsToUsersAndAuthentications < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :avatar_source, :string, default: "initials", null: false
    add_column :users, :has_gravatar, :boolean, default: false, null: false
    add_column :authentications, :avatar_url, :string
  end
end
