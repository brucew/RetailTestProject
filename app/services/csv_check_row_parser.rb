# Turns one CSV row into the attributes of a check, or says why it can't be
# imported. Every kind of check names a store, a product and a day; a
# subclass adds what the check observed (its HEADERS and #observed_attributes_for).
#
# Parsing is strict on purpose (A3): a value we can't read is rejected, never
# guessed.
class CsvCheckRowParser
  class RowRejected < StandardError; end

  CATALOG_HEADERS = {
    store: "Address",
    product: "Product Name",
    date: "Date"
  }.freeze

  def self.required_headers
    self::HEADERS.values
  end

  # Loads the store and product lookups once, so parsing a row never queries.
  def initialize
    @store_ids_by_address = Store.pluck(:address, :id).to_h
    @product_ids_by_name = Product.pluck(:name, :id).to_h
    @event_times_by_date = {}
  end

  # Returns a hash ready for insert_all.
  # Raises RowRejected, with a reason fit for an operator, when the row is unusable.
  def attributes_for(row)
    raise RowRejected, "blank line" if row.fields.all?(&:blank?)

    {
      store_id: id_for(@store_ids_by_address, row[CATALOG_HEADERS[:store]], "store"),
      product_id: id_for(@product_ids_by_name, row[CATALOG_HEADERS[:product]], "product"),
      event_time: event_time_for(row[CATALOG_HEADERS[:date]])
    }.merge(observed_attributes_for(row))
  end

  private

  def id_for(ids_by_key, key, record_name)
    ids_by_key.fetch(key) { raise RowRejected, "unknown #{record_name} #{key.inspect}" }
  end

  # Checks are date-granular and stored at midnight UTC whatever the app's
  # time zone, which is how pages read them back as dates. A file has a few
  # hundred distinct dates across a million rows, so each is parsed once.
  def event_time_for(date)
    @event_times_by_date[date] ||= calendar_date(date).to_time(:utc)
  end

  # Only YYYY-MM-DD: Date.iso8601 alone also accepts week and ordinal dates,
  # two-digit years, signed years and a time of day (which it drops).
  def calendar_date(date)
    raise Date::Error unless date&.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(date)
  rescue Date::Error
    raise RowRejected, "invalid date #{date.inspect} (expected YYYY-MM-DD)"
  end
end
