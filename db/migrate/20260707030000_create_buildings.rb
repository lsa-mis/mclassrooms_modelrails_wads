class CreateBuildings < ActiveRecord::Migration[8.1]
  def change
    create_table :buildings do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :campus, foreign_key: true
      t.string :bldrecnbr, null: false                     # natural key (header note 5)
      t.string :name, null: false
      t.string :abbreviation, :address, :city, :state, :zip, :country
      t.string :nickname                                   # curated
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.boolean :in_feed, null: false, default: false      # sync-owned (D6)
      t.datetime :hidden_at                                # curation-owned (D6)
      t.references :hidden_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :buildings, :bldrecnbr, unique: true
    add_index :buildings, :in_feed
    add_index :buildings, :hidden_at
  end
end
