module PriceChecks
  # Reads a shelf price in dollars and stores it as integer cents (D3).
  # Only plain decimals with at most two places are accepted, and they go
  # through BigDecimal, never Float, so "0.29" is 29 cents exactly. Anything
  # else ("$5", "5,00", "1.234", "-1", " 5", blank) is rejected rather than
  # guessed at.
  class CsvRowParser < CsvCheckRowParser
    HEADERS = CATALOG_HEADERS.merge(price: "Price").freeze

    private

    def observed_attributes_for(row)
      price = row[HEADERS[:price]]
      unless price&.match?(/\A\d+(\.\d{1,2})?\z/)
        raise RowRejected, "invalid price #{price.inspect} (expected dollars such as 4 or 4.99)"
      end

      price_cents = (BigDecimal(price) * 100).to_i
      raise RowRejected, "price #{price.inspect} is too large" if price_cents > largest_price_cents

      { price_cents: }
    end

    # price_cents is a bigint column; a larger value would abort the whole import.
    def largest_price_cents = (2**63) - 1
  end
end
