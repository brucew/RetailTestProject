module InventoryChecks
  # Imports inventory_checks.csv. The repository's data file was delivered as
  # tracking_events.csv, which is still read when the new name is absent (D14).
  class CsvImporter < CsvCheckImporter
    imports InventoryCheck, parsed_by: CsvRowParser,
                            unique_by: :index_inventory_checks_on_store_product_time_presence,
                            default_file_names: %w[inventory_checks.csv tracking_events.csv]
  end
end
