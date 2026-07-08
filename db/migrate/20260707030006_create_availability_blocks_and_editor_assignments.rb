class CreateAvailabilityBlocksAndEditorAssignments < ActiveRecord::Migration[8.1]
  def change
    # D11: busy/free state only — room_id + starts_at/ends_at, no other content
    # columns, ever. No column here may hold event details (title, course,
    # instructor, description, ...); see AvailabilityBlock's column-tripwire spec.
    create_table :availability_blocks do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.timestamps
    end
    add_index :availability_blocks, [ :room_id, :starts_at ]

    create_table :editor_assignments do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :unit, null: false, foreign_key: true
      t.timestamps
    end
    add_index :editor_assignments, [ :user_id, :unit_id ], unique: true
  end
end
