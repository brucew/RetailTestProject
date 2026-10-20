require "test_helper"

class PriceChecks::CsvImporterTest < ActiveSupport::TestCase
  setup do
    @log = StringIO.new
  end

  test "importing a valid file stores every row with its price in cents" do
    result = import("valid.csv")

    assert_equal [4, 4, 0, 0], counts(result)
    assert_equal [
      ["1 High Street, Bree", "Pony Pale Ale", Time.zone.local(2025, 1, 2), 499],
      ["1 High Street, Bree", "Pony Pale Ale", Time.zone.local(2025, 1, 3), 0],
      ["12 Bywater Road, Hobbiton", "Dragon Stout", Time.zone.local(2025, 1, 2), 50],
      ["12 Bywater Road, Hobbiton", "Pony Porter", Time.zone.local(2025, 1, 4), 125_000]
    ], imported_checks
  end

  test "rows priced as anything but plain dollars are rejected and the rest imported" do
    result = import("invalid_prices.csv")

    assert_equal [7, 1, 0, 6], counts(result)
    assert_equal [rejection(2, 'invalid price "-1" (expected dollars such as 4 or 4.99)'),
                  rejection(3, 'invalid price "1.234" (expected dollars such as 4 or 4.99)'),
                  rejection(4, 'invalid price "$5" (expected dollars such as 4 or 4.99)'),
                  rejection(5, 'invalid price "5,00" (expected dollars such as 4 or 4.99)'),
                  rejection(6, "invalid price nil (expected dollars such as 4 or 4.99)")], result.rejection_samples
    assert_equal [50], imported_checks.map(&:last)
  end

  test "rows naming an unknown store or product are rejected with the line and name" do
    result = import("unknown_store_and_product.csv")

    assert_equal [3, 1, 0, 2], counts(result)
    assert_equal [rejection(3, 'unknown store "99 Nowhere Lane, Mordor"'),
                  rejection(4, 'unknown product "Orc Draught"')], result.rejection_samples
  end

  test "rows with a date that isn't a real YYYY-MM-DD day are rejected" do
    result = assert_no_difference("PriceCheck.count") { import("invalid_dates.csv") }

    assert_equal [rejection(2, 'invalid date "02/01/2025" (expected YYYY-MM-DD)'),
                  rejection(3, "invalid date nil (expected YYYY-MM-DD)"),
                  rejection(4, 'invalid date "2025-02-30" (expected YYYY-MM-DD)')], result.rejection_samples
  end

  test "repeated prices are skipped as duplicates, including the same amount written differently" do
    result = import("duplicates.csv")

    assert_equal [5, 3, 2, 0], counts(result)
  end

  test "repeated prices from an earlier batch are skipped as duplicates too" do
    result = import("duplicates.csv", batch_size: 1)

    assert_equal [5, 3, 2, 0], counts(result)
  end

  test "different prices for the same store, product and day are all kept in file order" do
    import("duplicates.csv")

    assert_equal [499, 399], imported_checks.select { |check| check[1] == "Pony Pale Ale" }.map(&:last)
  end

  test "importing the same file again inserts nothing and counts every row as a duplicate" do
    import("valid.csv")

    result = assert_no_difference("PriceCheck.count") { import("valid.csv") }

    assert_equal [4, 0, 4, 0], counts(result)
  end

  test "a file with only a header imports nothing" do
    result = assert_no_difference("PriceCheck.count") { import("header_only.csv") }

    assert_equal [0, 0, 0, 0], counts(result)
  end

  test "a file without a Price header is refused before anything is imported" do
    error = assert_raises(PriceChecks::CsvImporter::MissingHeadersError) { import("missing_price_header.csv") }

    assert_match(/missing_price_header\.csv is missing required headers: Price\z/, error.message)
    assert_empty imported_checks
  end

  test "an inventory check export is refused as a price check export" do
    error = assert_raises(PriceChecks::CsvImporter::MissingHeadersError) do
      PriceChecks::CsvImporter.new(file_fixture("inventory_checks/valid.csv"), logger: Logger.new(@log)).import
    end

    assert_match(/missing required headers: Price\z/, error.message)
  end

  test "UTF-8 store and product names behind a byte order mark are matched exactly" do
    ["135 Strickland Propane Road, Arlen, Texas",
     "9¾ Platform Plaza, King’s Cross, Wizarding World"].each { |address| Store.create!(address:) }
    ["Nobleman’s Wine Reserve", "Pony-Rider’s Travel Rations"].each do |name|
      Product.create!(name:, brand: brands(:prancing_pony))
    end

    result = import("utf8_names.csv")

    assert_equal [2, 2, 0, 0], counts(result)
    assert_equal [["135 Strickland Propane Road, Arlen, Texas", "Nobleman’s Wine Reserve",
                   Time.zone.local(2025, 9, 16), 2499],
                  ["9¾ Platform Plaza, King’s Cross, Wizarding World", "Pony-Rider’s Travel Rations",
                   Time.zone.local(2025, 2, 22), 749]], imported_checks
  end

  test "the result is logged under the price importer's name" do
    import("unknown_store_and_product.csv")

    assert_includes @log.string, "[PriceChecks::CsvImporter] "
    assert_includes @log.string, "rows read=3 inserted=1 duplicates=0 rejected=2"
    assert_includes @log.string, 'rejected line 3: unknown store "99 Nowhere Lane, Mordor"'
  end

  test "an explicit source path is used even when price_checks.csv exists" do
    in_app_root_with("price_checks.csv", "elsewhere.csv") do |root|
      assert_equal root.join("elsewhere.csv"), PriceChecks::CsvImporter.locate_source(root.join("elsewhere.csv"), root:)
    end
  end

  test "an explicit source path that doesn't exist is reported, without falling back to price_checks.csv" do
    in_app_root_with("price_checks.csv") do |root|
      error = assert_raises(PriceChecks::CsvImporter::SourceNotFoundError) do
        PriceChecks::CsvImporter.locate_source(root.join("missing.csv"), root:)
      end

      assert_equal "No price checks CSV found. Looked for:\n  #{root.join('missing.csv')}", error.message
    end
  end

  test "without a path, price_checks.csv in the app root is used" do
    in_app_root_with("price_checks.csv") do |root|
      assert_equal root.join("price_checks.csv"), PriceChecks::CsvImporter.locate_source(root:)
    end
  end

  test "without price_checks.csv, inventory files are never picked up and only price_checks.csv is reported" do
    in_app_root_with("inventory_checks.csv", "tracking_events.csv") do |root|
      error = assert_raises(PriceChecks::CsvImporter::SourceNotFoundError) { PriceChecks::CsvImporter.locate_source(root:) }

      assert_equal "No price checks CSV found. Looked for:\n  #{root.join('price_checks.csv')}", error.message
    end
  end

  private

  def import(file_name, batch_size: 5_000)
    PriceChecks::CsvImporter.new(file_fixture("price_checks/#{file_name}"), batch_size:, logger: Logger.new(@log)).import
  end

  def counts(result)
    [result.rows_read, result.inserted, result.duplicates, result.rejected]
  end

  def rejection(line, reason)
    PriceChecks::CsvImporter::Rejection.new(line:, reason:)
  end

  def in_app_root_with(*file_names)
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      file_names.each { |name| FileUtils.touch(root.join(name)) }
      yield root
    end
  end

  # Fixture price checks are all from 2024; every file under test is dated 2025.
  def imported_checks
    PriceCheck.joins(:store, :product).where(event_time: Time.zone.local(2025, 1, 1)..).order(:id)
              .pluck("stores.address", "products.name", :event_time, :price_cents)
  end
end
