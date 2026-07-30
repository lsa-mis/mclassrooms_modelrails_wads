class AddMetadataToBuildingPhotos < ActiveRecord::Migration[8.1]
  def change
    add_column :buildings, :photo_alt, :string
    add_column :buildings, :photo_description, :text
    add_column :buildings, :photo_derived_ok, :boolean, default: false, null: false
  end
end
