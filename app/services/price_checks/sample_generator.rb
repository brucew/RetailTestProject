require "csv"

module PriceChecks
  # Writes a realistic, reproducible price_checks.csv for the catalog in the
  # database (A7), in the dialect of inventory_checks.csv (LF line endings).
  #
  # The same seed and catalog always give a byte-identical file. Prices model
  # a shelf: each product has a list price (log-uniform, $1-$500) that changes
  # 0-3 times over the year, each store prices a few percent above or below
  # it, about 5% of checks catch a 10-30% promotion, and every price ends in 9.
  #
  # So that the importer's dedupe and tie-breaking (A4) are exercised:
  # - duplicate_share of rows repeat an earlier row exactly (a resubmission),
  # - same_day_reprice_share of rows re-check an earlier store, product and
  #   day and find a lower price, which as the later row becomes current.
  # Every other row is a store, product and day not checked before, so those
  # shares are the only duplicates and same-day repricings in the file.
  class SampleGenerator
    SampleRow = Data.define(:address, :product_name, :date, :price_cents) do
      def to_csv
        CSV.generate_line([address, product_name, date.iso8601, format("%d.%02d", *price_cents.divmod(100))])
      end
    end

    # row_count:: data rows to write, not counting the header.
    def initialize(row_count:, seed: 20_241_205, duplicate_share: 0.02, same_day_reprice_share: 0.01)
      @row_count = row_count
      @random = Random.new(seed)
      @duplicate_share = duplicate_share
      @same_day_reprice_share = same_day_reprice_share
    end

    # Writes the header and rows to path and returns the number of rows written.
    # Raises ArgumentError when the catalog can't hold that many distinct checks.
    def write(path)
      rows = sample_rows
      File.open(path, "w", encoding: Encoding::UTF_8) do |file|
        file << CSV.generate_line(CsvRowParser.required_headers)
        rows.each { |row| file << row.to_csv }
      end
      rows.size
    end

    private

    def sample_rows
      load_catalog
      checked_days = Set.new
      @row_count.times.each_with_object([]) { |_index, rows| rows << next_row(rows, checked_days) }
    end

    # Sorted in Ruby rather than by the database, whose collation could
    # otherwise change the order, and with it every row, between machines.
    def load_catalog
      @addresses = Store.pluck(:address).sort
      @product_names = Product.pluck(:name).sort
      ensure_catalog_can_hold_every_row
      @store_price_factors = @addresses.index_with { @random.rand(0.95..1.05) }
      @list_price_histories = @product_names.index_with { list_price_history }
    end

    def ensure_catalog_can_hold_every_row
      capacity = @addresses.size * @product_names.size * days_in_sample
      return if (0..capacity).cover?(@row_count)

      raise ArgumentError, "Can't generate #{@row_count} distinct price checks from #{@addresses.size} stores, " \
                           "#{@product_names.size} products and #{days_in_sample} days"
    end

    def next_row(rows, checked_days)
      draw = @random.rand
      return fresh_row(checked_days) if rows.empty? || draw >= @duplicate_share + @same_day_reprice_share
      return rows.sample(random: @random) if draw < @duplicate_share

      same_day_reprice(rows.sample(random: @random))
    end

    def fresh_row(checked_days)
      day = loop do
        candidate = [@addresses.sample(random: @random), @product_names.sample(random: @random), random_date]
        break candidate if checked_days.add?(candidate)
      end
      address, product_name, date = day
      SampleRow.new(address:, product_name:, date:, price_cents: shelf_price_cents(address, product_name, date))
    end

    def shelf_price_cents(address, product_name, date)
      cents = list_price_cents(product_name, date) * @store_price_factors.fetch(address)
      cents *= @random.rand(0.7..0.9) if @random.rand < promotion_share
      ending_in_nine(cents)
    end

    # A markdown applied after an earlier check the same day.
    def same_day_reprice(row)
      price_cents = ending_in_nine(row.price_cents * @random.rand(0.75..0.95))
      row.with(price_cents: price_cents == row.price_cents ? price_cents + 10 : price_cents)
    end

    # [[first day, cents], [day of change, new cents], ...] in date order.
    def list_price_history
      cents = Math.exp(@random.rand(Math.log(100.0)..Math.log(50_000.0)))
      changes = Array.new(@random.rand(0..3)) { random_date }.sort
      [[sample_dates.begin, cents]] + changes.map { |date| [date, cents *= @random.rand(0.92..1.12)] }
    end

    def list_price_cents(product_name, date)
      @list_price_histories.fetch(product_name).reverse_each.find { |effective_date, _cents| effective_date <= date }.last
    end

    def ending_in_nine(cents)
      [((cents / 10.0).round * 10) - 1, 9].max
    end

    def random_date
      sample_dates.begin + @random.rand(days_in_sample)
    end

    # The same year the inventory checks cover.
    def sample_dates
      Date.new(2024, 12, 5)..Date.new(2025, 12, 5)
    end

    def days_in_sample
      (sample_dates.end - sample_dates.begin).to_i + 1
    end

    def promotion_share = 0.05
  end
end
