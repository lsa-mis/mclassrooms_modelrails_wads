class AddProgressToSyncPhases < ActiveRecord::Migration[8.1]
  def change
    add_column :sync_phases, :items_done, :integer
    add_column :sync_phases, :items_total, :integer
  end
end
