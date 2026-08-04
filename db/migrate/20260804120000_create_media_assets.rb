class CreateMediaAssets < ActiveRecord::Migration[8.1]
  def up
    # The graduation is free ONLY at zero rows. Assert rather than assume: an
    # orphaned attachment row pointing at a class name that no longer exists
    # breaks silently and forever.
    if table_exists?(:room_gallery_images)
      count = select_value("SELECT COUNT(*) FROM room_gallery_images").to_i
      raise "room_gallery_images has #{count} rows; this migration only supports zero" unless count.zero?
    end

    orphans = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM active_storage_attachments
      WHERE record_type IN ('RoomGalleryImage') OR (record_type = 'Room' AND name = 'photo')
    SQL
    raise "#{orphans} attachment rows would be orphaned; purge them first" unless orphans.zero?

    create_table :media_assets do |t|
      t.string  :owner_type, null: false
      t.integer :owner_id,   null: false
      t.integer :workspace_id, null: false
      t.integer :position, null: false, default: 1
      t.string  :subject
      t.string  :image_alt
      t.text    :image_description
      t.boolean :image_derived_ok, null: false, default: false
      t.timestamps
    end

    add_index :media_assets, [ :owner_type, :owner_id, :position ]
    add_index :media_assets, [ :workspace_id, :subject ]
    add_foreign_key :media_assets, :workspaces

    # owner_type is stable in a way `subject` is not, so it earns a constraint.
    # Named _v1 and dropped when Buildings become owners.
    add_check_constraint :media_assets, "owner_type = 'Room'",
      name: "media_assets_owner_type_v1"

    drop_table :room_gallery_images

    # Room#photo is removed: every room still now lives in the gallery.
    remove_column :rooms, :photo_alt
    remove_column :rooms, :photo_description
    remove_column :rooms, :photo_derived_ok
  end

  def down
    add_column :rooms, :photo_alt, :string
    add_column :rooms, :photo_description, :text
    add_column :rooms, :photo_derived_ok, :boolean, null: false, default: false

    create_table :room_gallery_images do |t|
      t.integer :room_id, null: false
      t.integer :workspace_id, null: false
      t.integer :position, null: false, default: 0
      t.string  :image_alt
      t.text    :image_description
      t.boolean :image_derived_ok, null: false, default: false
      t.timestamps
    end
    add_index :room_gallery_images, [ :room_id, :position ]
    add_index :room_gallery_images, :workspace_id
    add_foreign_key :room_gallery_images, :rooms

    drop_table :media_assets
  end
end
