module InventoryChecks
  # Imports inventory_checks.csv. The repository's data file was delivered as
  # tracking_events.csv, which is still read when the new name is absent (D14).
  class CsvImporter < CsvCheckImporter
    imports InventoryCheck, parsed_by: CsvRowParser,
                            unique_by: :index_inventory_checks_on_store_product_time_presence,
                            default_file_names: %w[inventory_checks.csv tracking_events.csv]

    private

    # Alerts are derived from the checks (D7). A new check can start, extend,
    # resolve, split or move a streak anywhere in its timeline, so each pair
    # that gained a check is reconciled in full; other pairs can't change.
    def reconcile_derived_records(changed_pairs)
      InventoryAlerts::Reconciler.new(pairs: changed_pairs).reconcile
    end
  end
end
