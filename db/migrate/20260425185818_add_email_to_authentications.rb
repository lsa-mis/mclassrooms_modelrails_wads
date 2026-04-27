class AddEmailToAuthentications < ActiveRecord::Migration[8.1]
  def change
    add_column :authentications, :email, :string
  end
end
