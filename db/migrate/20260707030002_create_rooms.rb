class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :building, null: false, foreign_key: true
      t.references :floor, foreign_key: true      # linked by sync (D10)
      t.references :campus, foreign_key: true
      t.references :unit, foreign_key: true       # nil ⇒ admin-only curation (Brief §14.1)
      t.string :rmrecnbr, null: false              # natural key
      t.string :room_number, :room_type
      t.string :department_id, :department_description, :department_group, :department_group_description
      t.integer :square_feet, :instructional_seat_count
      t.string :facility_code, :facility_code_normalized
      t.string :building_name                      # sync-denormalized (Brief §4.2); FTS source
      t.string :nickname                           # curated
      t.integer :ada_seat_count                    # curated
      t.boolean :in_feed, null: false, default: false   # sync-owned (D6)
      t.datetime :hidden_at                        # curation-owned (D6)
      t.references :hidden_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :rooms, :rmrecnbr, unique: true
    add_index :rooms, :facility_code_normalized
    add_index :rooms, [ :room_type, :instructional_seat_count ]
    add_index :rooms, :in_feed
    add_index :rooms, :hidden_at
  end
end
