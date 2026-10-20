require "test_helper"

class TrackingEventTest < ActiveSupport::TestCase
  test "a tracking event links the product and store that were checked" do
    event = tracking_events(:stout_sold_out_at_hobbiton)

    assert_equal products(:dragon_stout), event.product
    assert_equal stores(:hobbiton_bywater_road), event.store
  end

  test "a tracking event records whether inventory was present and when" do
    event = tracking_events(:pale_ale_sold_out_at_bree)

    assert_equal false, event.inventory_present
    assert_equal Time.zone.parse("2024-03-02 09:00:00"), event.event_time
  end

  test "a tracking event is invalid without a product or store" do
    event = TrackingEvent.new(inventory_present: true, event_time: Time.current)

    assert_not event.valid?
    assert_equal ["must exist"], event.errors[:product]
    assert_equal ["must exist"], event.errors[:store]
  end
end
