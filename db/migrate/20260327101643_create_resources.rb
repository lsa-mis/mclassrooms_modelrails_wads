class CreateResources < ActiveRecord::Migration[8.1]
  def change
    create_table :resources do |t|
      t.references :project, null: false, foreign_key: true
      t.string :resourceable_type, null: false
      t.integer :resourceable_id, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "draft"
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.integer :position, null: false, default: 0
      t.datetime :discarded_at

      t.timestamps
    end

    add_index :resources, [:project_id, :position]
    add_index :resources, [:resourceable_type, :resourceable_id], unique: true
    add_index :resources, :discarded_at
  end
end
