module InventoryChecks
  # Turns one CSV row into the attributes of an inventory check, or says why it
  # can't be imported. Parsing is strict on purpose (A3): a value we can't read
  # is rejected, never guessed — a blank "Inventory Present" read as false
  # would record a stockout that never happened.
  class CsvRowParser
    class RowRejected < StandardError; end

    HEADERS = {
      store: "Address",
      product: "Product Name",
      date: "Date",
      inventory_present: "Inventory Present"
    }.freeze

    # Loads the store and product lookups once, so parsing a row never queries.
    def initialize
      @store_ids_by_address = Store.pluck(:address, :id).to_h
      @product_ids_by_name = Product.pluck(:name, :id).to_h
      @event_times_by_date = {}
    end

    # Returns a hash ready for InventoryCheck.insert_all.
    # Raises RowRejected, with a reason fit for an operator, when the row is unusable.
    def attributes_for(row)
      {
        store_id: id_for(@store_ids_by_address, row[HEADERS[:store]], "store"),
        product_id: id_for(@product_ids_by_name, row[HEADERS[:product]], "product"),
        event_time: event_time_for(row[HEADERS[:date]]),
        inventory_present: inventory_present_for(row[HEADERS[:inventory_present]])
      }
    end

    private

    def id_for(ids_by_key, key, record_name)
      ids_by_key.fetch(key) { raise RowRejected, "unknown #{record_name} #{key.inspect}" }
    end

    # The file has a few hundred distinct dates across a million rows, so each
    # is parsed once. Checks are date-granular and stored at midnight in the app
    # time zone, like the rows imported before this importer existed.
    def event_time_for(date)
      @event_times_by_date[date] ||= Date.iso8601(date).in_time_zone
    rescue Date::Error, TypeError
      raise RowRejected, "invalid date #{date.inspect} (expected YYYY-MM-DD)"
    end

    def inventory_present_for(value)
      case value&.downcase
      when "true" then true
      when "false" then false
      else raise RowRejected, "invalid inventory present #{value.inspect} (expected True or False)"
      end
    end
  end
end
