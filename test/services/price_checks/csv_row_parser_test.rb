require "test_helper"
require "csv"

class PriceChecks::CsvRowParserTest < ActiveSupport::TestCase
  setup do
    @parser = PriceChecks::CsvRowParser.new
  end

  test "a row becomes the ids, midnight timestamp and price in cents of a price check" do
    attributes = @parser.attributes_for(row(date: "2025-01-02", price: "4.99"))

    assert_equal({ store_id: stores(:bree_high_street).id, product_id: products(:pony_porter).id,
                   event_time: Time.zone.local(2025, 1, 2), price_cents: 499 }, attributes)
  end

  test "whole dollars, one and two decimal places and zero are all read exactly as cents" do
    prices = %w[0 0.5 0.29 4.9 4.90 12 1250.01 0.01].map { |price| @parser.attributes_for(row(price:))[:price_cents] }

    assert_equal [0, 50, 29, 490, 490, 1200, 125_001, 1], prices
  end

  test "prices that aren't plain dollars with at most two decimals are rejected" do
    ["-1", "1.234", "$5", "5,00", "", nil, " 5", "5 ", "5.", ".5", "1e3", "five", "4.99 USD"].each do |price|
      error = assert_raises(PriceChecks::CsvRowParser::RowRejected, "expected #{price.inspect} to be rejected") do
        @parser.attributes_for(row(price:))
      end

      assert_equal "invalid price #{price.inspect} (expected dollars such as 4 or 4.99)", error.message
    end
  end

  test "a price too large for the price column is rejected instead of aborting the import" do
    error = assert_raises(PriceChecks::CsvRowParser::RowRejected) do
      @parser.attributes_for(row(price: "92233720368547758.08"))
    end

    assert_equal 'price "92233720368547758.08" is too large', error.message
    assert_equal (2**63) - 1, @parser.attributes_for(row(price: "92233720368547758.07"))[:price_cents]
  end

  test "an unknown store or product is rejected by name" do
    error = assert_raises(PriceChecks::CsvRowParser::RowRejected) do
      @parser.attributes_for(row(address: "99 Nowhere Lane, Mordor"))
    end

    assert_equal 'unknown store "99 Nowhere Lane, Mordor"', error.message
  end

  test "a date with a time of day is rejected, since checks are recorded per day" do
    error = assert_raises(PriceChecks::CsvRowParser::RowRejected) do
      @parser.attributes_for(row(date: "2025-01-02 10:00"))
    end

    assert_equal 'invalid date "2025-01-02 10:00" (expected YYYY-MM-DD)', error.message
  end

  test "the required headers are the catalog columns followed by Price" do
    assert_equal ["Address", "Product Name", "Date", "Price"], PriceChecks::CsvRowParser.required_headers
  end

  private

  def row(address: "1 High Street, Bree", product_name: "Pony Porter", date: "2025-01-02", price: "4.99")
    CSV::Row.new(PriceChecks::CsvRowParser.required_headers, [address, product_name, date, price])
  end
end
