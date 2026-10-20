require "test_helper"

class BrandTest < ActiveSupport::TestCase
  test "a brand lists only its own products" do
    assert_equal [products(:pony_pale_ale), products(:pony_porter)],
                 brands(:prancing_pony).products.order(:name).to_a
  end

  test "a brand with a single product lists just that product" do
    assert_equal [products(:dragon_stout)], brands(:green_dragon).products.to_a
  end
end
