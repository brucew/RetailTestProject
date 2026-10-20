class RenameTrackingEventsToInventoryChecks < ActiveRecord::Migration[7.1]
  def change
    rename_table :tracking_events, :inventory_checks
  end
end
