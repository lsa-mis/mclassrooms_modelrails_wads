class CreateAuthentications < ActiveRecord::Migration[8.1]
  def change
    create_table :authentications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider
      t.string :uid
      t.string :oauth_token
      t.string :oauth_refresh_token
      t.datetime :oauth_expires_at
      t.string :verification_token
      t.datetime :verification_sent_at
      t.datetime :verified_at

      t.timestamps
    end

    add_index :authentications, [:user_id, :provider], unique: true
    add_index :authentications, [:provider, :uid], unique: true
    add_index :authentications, :verification_token, unique: true
  end
end
