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
    # in the file is reconciled in full. That includes pairs whose rows were
    # all duplicates: re-importing a file then also repairs alerts that are
    # missing or out of date for checks already stored. Pairs the file
    # doesn't name are left alone.
    def reconcile_derived_records(imported_pairs)
      InventoryAlerts::Reconciler.new(pairs: imported_pairs).reconcile
    end
  end
end
