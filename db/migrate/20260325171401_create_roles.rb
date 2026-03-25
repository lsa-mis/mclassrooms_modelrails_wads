class CreateRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :roles do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.json :permissions, default: {}
      t.references :workspace, null: true, foreign_key: true

      t.timestamps
    end

    add_index :roles, [:workspace_id, :slug], unique: true
  end
end
