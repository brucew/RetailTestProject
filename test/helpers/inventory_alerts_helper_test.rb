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

  test "links a brand's open-alert count to the alerts index filtered to that brand's open alerts" do
    brand = brands(:green_dragon)

    assert_dom_equal %(<a href="/inventory_alerts?brand_id=#{brand.id}&amp;status=open">1,234</a>),
                     open_alerts_link(brand, 1234)
  end

  test "shows a zero open-alert count without a link" do
    assert_equal "0", open_alerts_link(brands(:green_dragon), 0)
  end
end
