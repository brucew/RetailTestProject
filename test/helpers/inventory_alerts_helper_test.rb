require "test_helper"

class InventoryAlertsHelperTest < ActionView::TestCase
  test "labels an alert whose product is still out of stock as open" do
    assert_dom_equal %(<span class="status status--open">Open</span>),
                     alert_status_tag(InventoryAlert.new(resolved_at: nil))
  end

  test "labels an alert whose product was restocked as resolved" do
    assert_dom_equal %(<span class="status status--resolved">Resolved</span>),
                     alert_status_tag(InventoryAlert.new(resolved_at: Time.utc(2024, 3, 7)))
  end
end
