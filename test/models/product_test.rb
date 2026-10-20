require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "a product belongs to its brand" do
    assert_equal brands(:green_dragon), products(:dragon_stout).brand
  end

  test "a product lists its inventory checks across stores" do
    assert_equal [inventory_checks(:pale_ale_in_stock_at_bree), inventory_checks(:pale_ale_sold_out_at_bree)],
                 products(:pony_pale_ale).inventory_checks.order(:event_time).to_a
  end

  test "a product is invalid without a brand" do
    product = Product.new(name: "Unbranded Cider")

    assert_not product.valid?
    assert_equal ["must exist"], product.errors[:brand]
  end

  test "a product needs a name" do
    product = Product.new(name: "", brand: brands(:prancing_pony))

    assert_not product.valid?
    assert_equal ["can't be blank"], product.errors[:name]
  end

  test "two products cannot share a name, because the importer finds products by name" do
    product = Product.new(name: products(:dragon_stout).name, brand: brands(:prancing_pony))

    assert_not product.valid?
    assert_equal ["has already been taken"], product.errors[:name]
  end

  test "a product with inventory checks cannot be deleted" do
    product = products(:dragon_stout)

    assert_not product.destroy
    assert Product.exists?(product.id)
  end
end
