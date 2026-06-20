class AddSharedWithClientToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :shared_with_client, :boolean, null: false, default: false
  end
end
