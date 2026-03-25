class RenamePasswordResetTokenColumns < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :password_reset_token, :reset_password_token
    rename_column :users, :password_reset_sent_at, :reset_password_sent_at
  end
end
