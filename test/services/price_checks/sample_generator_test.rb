require "test_helper"
require "csv"

class PriceChecks::SampleGeneratorTest < ActiveSupport::TestCase
  test "the same seed and catalog give a byte-identical file" do
    first = generate(row_count: 300, seed: 7)
    second = generate(row_count: 300, seed: 7)

    assert_equal first, second
    assert_not_equal first, generate(row_count: 300, seed: 8)
  end

  test "the file has the price check header, LF line endings and the requested number of rows" do
    lines = generate(row_count: 250).lines

    assert_equal "Address,Product Name,Date,Price\n", lines.first
    assert_equal 251, lines.size
    assert lines.all? { |line| line.end_with?("\n") && !line.end_with?("\r\n") }
  end

  test "rows name catalog stores and products, dates within the sample year and plain dollar prices" do
    rows = generated_rows(row_count: 500)

    assert_equal Store.pluck(:address).sort, rows.map { |row| row["Address"] }.uniq.sort
    assert_equal Product.pluck(:name).sort, rows.map { |row| row["Product Name"] }.uniq.sort
    assert rows.all? { |row| (Date.new(2024, 12, 5)..Date.new(2025, 12, 5)).cover?(Date.iso8601(row["Date"])) }
    assert rows.all? { |row| row["Price"].match?(/\A\d+\.\d9\z/) }
    # $1-$500 list prices, moved by at most three 12% rises and a 5% store premium.
    assert rows.all? { |row| (BigDecimal("0.09")..BigDecimal("740")).cover?(BigDecimal(row["Price"])) }
  end

  test "the importer accepts every generated row and skips exactly the repeated ones" do
    rows = generated_rows(row_count: 500)
    repeats = rows.size - rows.map(&:fields).uniq.size

    Tempfile.create(%w[price_checks .csv]) do |file|
      File.write(file.path, generate(row_count: 500))
      result = PriceChecks::CsvImporter.new(file.path, logger: Logger.new(nil)).import

      assert_equal [500, 500 - repeats, repeats, 0],
                   [result.rows_read, result.inserted, result.duplicates, result.rejected]
    end
  end

  test "about the documented share of rows are exact repeats or same-day repricings" do
    rows = generated_rows(row_count: 1_000, duplicate_share: 0.1, same_day_reprice_share: 0.1)

    exact_repeats = rows.size - rows.map(&:fields).uniq.size
    repriced_days = rows.map(&:fields).uniq.group_by { |fields| fields.first(3) }.values.sum { |checks| checks.size - 1 }

    assert_in_delta 100, exact_repeats, 30
    assert_in_delta 100, repriced_days, 30
  end

  test "by default about 2% of rows repeat and 1% reprice the same day" do
    rows = generated_rows(row_count: 2_000)

    assert_in_delta 40, rows.size - rows.map(&:fields).uniq.size, 20
    assert_in_delta 20, rows.map(&:fields).uniq.group_by { |fields| fields.first(3) }.values.sum { |checks| checks.size - 1 }, 14
  end

  test "asking for more distinct checks than the catalog has days for is refused" do
    capacity = Store.count * Product.count * 366

    error = assert_raises(ArgumentError) { generate(row_count: capacity + 1) }

    assert_equal "Can't generate #{capacity + 1} distinct price checks from #{Store.count} stores, " \
                 "#{Product.count} products and 366 days", error.message
  end

  test "an empty catalog can't produce any rows" do
    PriceCheck.delete_all
    InventoryCheck.delete_all
    Store.delete_all

    assert_raises(ArgumentError) { generate(row_count: 1) }
    assert_equal "Address,Product Name,Date,Price\n", generate(row_count: 0)
  end

  private

  def generate(row_count:, **options)
    Tempfile.create(%w[price_checks .csv]) do |file|
      PriceChecks::SampleGenerator.new(row_count:, **options).write(file.path)
      File.read(file.path, encoding: Encoding::UTF_8)
    end
  end

  def generated_rows(row_count:, **options)
    CSV.parse(generate(row_count:, **options), headers: true).to_a.drop(1).map do |fields|
      CSV::Row.new(PriceChecks::CsvRowParser.required_headers, fields)
    end
  end
end
