class CreateRoomContactsAndGalleryImages < ActiveRecord::Migration[8.1]
  def change
    create_table :room_contacts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true, index: { unique: true }
      t.string :scheduling_name
      t.string :scheduling_email
      t.string :scheduling_phone
      t.string :scheduling_detail_url
      t.string :scheduling_usage_guidelines_url
      t.string :support_department_id
      t.string :support_department_description
      t.string :support_email
      t.string :support_phone
      t.string :support_url
      t.timestamps
    end

    create_table :room_gallery_images do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :room_gallery_images, [ :room_id, :position ]
  end
end
