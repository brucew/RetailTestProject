module PriceChecks
  # Imports price_checks.csv. Prices arrived after the rename to "checks",
  # so there's no legacy file name to fall back to.
  class CsvImporter < CsvCheckImporter
    imports PriceCheck, parsed_by: CsvRowParser,
                        unique_by: :index_price_checks_on_store_product_time_price,
                        default_file_names: %w[price_checks.csv]
  end
end
