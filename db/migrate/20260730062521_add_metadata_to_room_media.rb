class AddMetadataToRoomMedia < ActiveRecord::Migration[8.1]
  def change
    %i[photo panorama seating_chart].each do |slot|
      add_column :rooms, :"#{slot}_alt", :string
      add_column :rooms, :"#{slot}_description", :text
      add_column :rooms, :"#{slot}_derived_ok", :boolean, default: false, null: false
    end
  end
end
