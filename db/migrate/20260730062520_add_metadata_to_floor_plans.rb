class AddMetadataToFloorPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :floors, :plan_alt, :string
    add_column :floors, :plan_description, :text
    add_column :floors, :plan_derived_ok, :boolean, default: false, null: false
  end
end
