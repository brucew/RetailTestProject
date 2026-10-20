require "test_helper"

class InventoryChecksHelperTest < ActionView::TestCase
  test "shows when a check happened as a date, without the time of day" do
    check = InventoryCheck.new(event_time: Time.utc(2024, 3, 1))

    assert_dom_equal %(<time datetime="2024-03-01">2024-03-01</time>), check_date_tag(check)
  end

  test "keeps the stored UTC date when the app runs in a zone behind UTC" do
    check = InventoryCheck.new(event_time: Time.utc(2024, 3, 1))

    Time.use_zone("Pacific Time (US & Canada)") do
      assert_dom_equal %(<time datetime="2024-03-01">2024-03-01</time>), check_date_tag(check)
    end
  end

  test "labels a check that found the product on the shelf as in stock" do
    assert_dom_equal %(<span class="status status--in-stock">In stock</span>),
                     inventory_status_tag(InventoryCheck.new(inventory_present: true))
  end

  test "labels a check that did not find the product as out of stock" do
    assert_dom_equal %(<span class="status status--out-of-stock">Out of stock</span>),
                     inventory_status_tag(InventoryCheck.new(inventory_present: false))
  end
end
