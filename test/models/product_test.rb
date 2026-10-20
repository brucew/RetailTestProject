require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "a product belongs to its brand" do
    assert_equal brands(:green_dragon), products(:dragon_stout).brand
  end

  test "a product lists its inventory checks across checks" do
    assert_equal [inventory_checks(:pale_ale_in_stock_at_bree), inventory_checks(:pale_ale_sold_out_at_bree)],
                 products(:pony_pale_ale).inventory_checks.order(:event_time).to_a
  end

  test "a product is invalid without a brand" do
    product = Product.new(name: "Unbranded Cider")

    assert_not product.valid?
    assert_equal ["must exist"], product.errors[:brand]
  end
end
