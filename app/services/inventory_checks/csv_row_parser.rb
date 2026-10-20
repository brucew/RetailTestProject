module InventoryChecks
  # Reads whether inventory was present. A blank "Inventory Present" read as
  # false would record a stockout that never happened, so only True and False
  # (in any letter case) are accepted (A3).
  class CsvRowParser < CsvCheckRowParser
    HEADERS = CATALOG_HEADERS.merge(inventory_present: "Inventory Present").freeze

    private

    def observed_attributes_for(row)
      value = row[HEADERS[:inventory_present]]
      inventory_present = case value&.downcase
                          when "true" then true
                          when "false" then false
                          else raise RowRejected, "invalid inventory present #{value.inspect} (expected True or False)"
                          end
      { inventory_present: }
    end
  end
end
