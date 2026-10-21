require "test_helper"
require "csv"

class InventoryChecks::CsvRowParserTest < ActiveSupport::TestCase
  setup do
    @parser = InventoryChecks::CsvRowParser.new
  end

  test "a row becomes the ids, midnight timestamp and presence of an inventory check" do
    attributes = @parser.attributes_for(row(date: "2025-01-02", inventory_present: "True"))

    assert_equal({ store_id: stores(:bree_high_street).id, product_id: products(:pony_porter).id,
                   event_time: Time.utc(2025, 1, 2), inventory_present: true }, attributes)
  end

  test "inventory presence is read regardless of letter case" do
    presences = %w[True TRUE true False FALSE false].map do |value|
      @parser.attributes_for(row(inventory_present: value))[:inventory_present]
    end

    assert_equal [true, true, true, false, false, false], presences
  end

  test "inventory presence padded with spaces is rejected rather than guessed" do
    error = assert_raises(InventoryChecks::CsvRowParser::RowRejected) do
      @parser.attributes_for(row(inventory_present: " True"))
    end

    assert_equal 'invalid inventory present " True" (expected True or False)', error.message
  end

  test "a date with a time of day is rejected, since checks are recorded per day" do
    error = assert_raises(InventoryChecks::CsvRowParser::RowRejected) do
      @parser.attributes_for(row(date: "2025-01-02 10:00"))
    end

    assert_equal 'invalid date "2025-01-02 10:00" (expected YYYY-MM-DD)', error.message
  end

  test "only plain calendar dates are accepted, not the other ISO 8601 forms" do
    rejected = %w[20250102 2025-W01-4 2025-002 25-01-02 +2025-01-02 -2025-01-02 2025-01-02T10:00:00 2025-02-30 2025-1-2]
    rejected += ["", nil]

    rejected.each do |date|
      error = assert_raises(InventoryChecks::CsvRowParser::RowRejected, date.inspect) { @parser.attributes_for(row(date:)) }
      assert_equal "invalid date #{date.inspect} (expected YYYY-MM-DD)", error.message
    end
  end

  test "a check is stored at midnight UTC, whatever the app's time zone" do
    %w[Tokyo Pacific/Honolulu].each do |zone|
      event_time = Time.use_zone(zone) { InventoryChecks::CsvRowParser.new.attributes_for(row(date: "2025-01-02"))[:event_time] }

      assert_equal Time.utc(2025, 1, 2), event_time, zone
    end
  end

  test "a blank line is rejected as blank, not as an unknown store" do
    error = assert_raises(InventoryChecks::CsvRowParser::RowRejected) do
      @parser.attributes_for(row(address: nil, product_name: nil, date: nil, inventory_present: nil))
    end

    assert_equal "blank line", error.message
  end

  test "parsing rows runs no queries once the parser is built" do
    queries = []
    counter = ->(*, payload) { queries << payload[:sql] }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      @parser.attributes_for(row)
      @parser.attributes_for(row(address: "12 Bywater Road, Hobbiton", product_name: "Dragon Stout"))
    end

    assert_empty queries
  end

  private

  def row(address: "1 High Street, Bree", product_name: "Pony Porter", date: "2025-01-02", inventory_present: "True")
    CSV::Row.new(InventoryChecks::CsvRowParser::HEADERS.values, [address, product_name, date, inventory_present])
  end
end
