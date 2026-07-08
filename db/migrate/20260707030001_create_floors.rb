class CreateFloors < ActiveRecord::Migration[8.1]
  def change
    create_table :floors do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :building, null: false, foreign_key: true
      t.string :label, null: false
      t.timestamps
    end
    add_index :floors, [ :building_id, :label ], unique: true
  end
end
