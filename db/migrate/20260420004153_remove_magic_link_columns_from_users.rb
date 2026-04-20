class RemoveMagicLinkColumnsFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :magic_link_token
    remove_column :users, :magic_link_token, :string
    remove_column :users, :magic_link_sent_at, :datetime
  end
end
