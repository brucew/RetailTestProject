class CreateInventoryAlerts < ActiveRecord::Migration[7.1]
  # One alert per out-of-stock streak: two or more consecutive "no inventory"
  # checks for a product at a store, in event_time order (D5). Alerts are
  # derived from the checks and kept in step with them by the reconciler (D7).
  def change
    create_table :inventory_alerts do |t|
      # The alert is addressed to the brand. Stored rather than joined through
      # products so per-brand listings and counts read one table (A9).
      t.references :brand, null: false, index: false, foreign_key: { name: "fk_inventory_alerts_brand" }
      t.references :store, null: false, index: false, foreign_key: { name: "fk_inventory_alerts_store" }
      t.references :product, null: false, index: false, foreign_key: { name: "fk_inventory_alerts_product" }
      # The streak's first miss identifies the alert; its second miss raised it;
      # the first in-stock check after the streak, if any, resolved it.
      t.references :streak_start_check, null: false, index: { unique: true },
                                        foreign_key: { to_table: :inventory_checks, name: "fk_inventory_alerts_streak_start_check" }
      t.references :triggering_check, null: false, index: false,
                                      foreign_key: { to_table: :inventory_checks, name: "fk_inventory_alerts_triggering_check" }
      t.references :resolving_check, index: false,
                                     foreign_key: { to_table: :inventory_checks, name: "fk_inventory_alerts_resolving_check" }
      t.datetime :started_at, null: false
      t.datetime :triggered_at, null: false
      t.datetime :resolved_at
      t.integer :miss_count, null: false
      t.timestamps

      t.check_constraint "miss_count >= 2", name: "inventory_alerts_streak_has_two_misses"
      t.check_constraint "(resolved_at IS NULL) = (resolving_check_id IS NULL)",
                         name: "inventory_alerts_resolved_with_a_check"
    end

    # Alerts index (newest first, optionally per brand) and brand pages.
    add_index :inventory_alerts, %i[brand_id triggered_at]
    # Reconciling one store/product pair at a time.
    add_index :inventory_alerts, %i[store_id product_id]
  end
end
