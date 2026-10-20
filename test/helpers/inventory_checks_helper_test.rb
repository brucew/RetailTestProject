require "test_helper"

class InventoryChecksHelperTest < ActionView::TestCase
  test "labels a check that found the product on the shelf as in stock" do
    assert_dom_equal %(<span class="status status--in-stock">In stock</span>),
                     inventory_status_tag(InventoryCheck.new(inventory_present: true))
  end

  test "labels a check that did not find the product as out of stock" do
    assert_dom_equal %(<span class="status status--out-of-stock">Out of stock</span>),
                     inventory_status_tag(InventoryCheck.new(inventory_present: false))
  end
end
