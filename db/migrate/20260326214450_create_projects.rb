class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :slug, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :primary_color
      t.datetime :discarded_at

      t.timestamps
    end

    add_index :projects, [:workspace_id, :slug], unique: true
    add_index :projects, :discarded_at
  end
end
