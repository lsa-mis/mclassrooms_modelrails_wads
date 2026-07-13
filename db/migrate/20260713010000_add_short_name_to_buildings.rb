class AddShortNameToBuildings < ActiveRecord::Migration[8.1]
  # Curated compact display name for room cards / tight layouts (backlog #8):
  # "CHEMISTRY AND DOW WILLARD H LABORATORY" humanizes fine but never gets
  # SHORT. Admin-editable through the audited building edit flow, never
  # touched by the vendor sync. Not indexed: display-only, never queried.
  def change
    add_column :buildings, :short_name, :string
  end
end
