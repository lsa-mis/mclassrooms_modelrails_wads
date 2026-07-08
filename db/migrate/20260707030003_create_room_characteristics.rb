class CreateRoomCharacteristics < ActiveRecord::Migration[8.1]
  def change
    create_table :room_characteristics do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true
      t.string :code, null: false
      t.string :short_code, null: false
      t.string :description
      t.string :long_description
      t.string :status

      t.timestamps
    end
    add_index :room_characteristics, [ :room_id, :code ], unique: true
    add_index :room_characteristics, :short_code
  end
end
