module PriceChecksHelper
  # Prices are stored as whole US cents (D3). Dividing a BigDecimal keeps the
  # conversion exact; a Float would turn some cent values into rounding errors.
  def format_price(price_cents)
    number_to_currency(BigDecimal(price_cents) / 100)
  end
end
