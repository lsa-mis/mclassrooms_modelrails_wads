class AddPrimaryColorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :primary_color, :integer, default: 210
  end
end
