class CreateNotesAndAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :notes do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :notable, polymorphic: true, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :parent, foreign_key: { to_table: :notes }
      t.boolean :alert, null: false, default: false
      t.timestamps
    end

    create_table :announcements do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :slot, null: false
      t.timestamps
    end
    add_index :announcements, :slot, unique: true
  end
end
