require "test_helper"

class BrandTest < ActiveSupport::TestCase
  test "a brand lists only its own products" do
    assert_equal [products(:pony_pale_ale), products(:pony_porter)],
                 brands(:prancing_pony).products.order(:name).to_a
  end

  test "a brand with a single product lists just that product" do
    assert_equal [products(:dragon_stout)], brands(:green_dragon).products.to_a
  end

  test "a brand needs a name" do
    brand = Brand.new(name: "")

    assert_not brand.valid?
    assert_equal ["can't be blank"], brand.errors[:name]
  end

  test "two brands cannot share a name" do
    brand = Brand.new(name: brands(:prancing_pony).name)

    assert_not brand.valid?
    assert_equal ["has already been taken"], brand.errors[:name]
  end

  test "a brand with products cannot be deleted" do
    brand = brands(:green_dragon)

    assert_not brand.destroy
    assert Brand.exists?(brand.id)
  end
end
