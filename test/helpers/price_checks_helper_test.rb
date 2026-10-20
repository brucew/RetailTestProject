require "test_helper"

class PriceChecksHelperTest < ActionView::TestCase
  test "formats a price in cents as US dollars" do
    assert_equal "$4.75", format_price(475)
  end

  test "formats a free product as zero dollars" do
    assert_equal "$0.00", format_price(0)
  end

  test "keeps the leading zero for prices under a dollar" do
    assert_equal "$0.50", format_price(50)
    assert_equal "$0.07", format_price(7)
  end

  test "separates thousands" do
    assert_equal "$1,234.56", format_price(123_456)
  end

  test "formats large prices exactly, without floating-point error" do
    assert_equal "$90,071,992,547,409.93", format_price(9_007_199_254_740_993)
  end
end
