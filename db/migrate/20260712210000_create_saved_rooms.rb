class CreateSavedRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_rooms do |t|
      # user index deliberately skipped — the composite unique below serves
      # every by-user lookup via its leading column
      t.references :user, null: false, foreign_key: true, index: false
      t.references :room, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.timestamps
    end

    # One save per (user, room); the DB constraint backs the model validation
    # so concurrent double-clicks can't slip a duplicate through.
    add_index :saved_rooms, [ :user_id, :room_id ], unique: true
  end
end
