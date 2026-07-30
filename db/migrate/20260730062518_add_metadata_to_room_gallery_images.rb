class AddMetadataToRoomGalleryImages < ActiveRecord::Migration[8.1]
  def change
    add_column :room_gallery_images, :image_alt, :string
    add_column :room_gallery_images, :image_description, :text
    add_column :room_gallery_images, :image_derived_ok, :boolean, default: false, null: false
  end
end
