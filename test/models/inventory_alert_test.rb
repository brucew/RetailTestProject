require "test_helper"

class InventoryAlertTest < ActiveSupport::TestCase
  test "an alert is addressed to the brand and points at the checks of its streak" do
    alert = inventory_alerts(:porter_out_at_hobbiton)

    assert_equal brands(:prancing_pony), alert.brand
    assert_equal stores(:hobbiton_bywater_road), alert.store
    assert_equal products(:pony_porter), alert.product
    assert_equal inventory_checks(:porter_sold_out_at_hobbiton), alert.streak_start_check
    assert_equal inventory_checks(:porter_still_sold_out_at_hobbiton), alert.triggering_check
    assert_equal inventory_checks(:porter_restocked_at_hobbiton), alert.resolving_check
  end

  test "an alert is open until inventory is seen again" do
    assert inventory_alerts(:stout_out_at_hobbiton).open?
    assert_not inventory_alerts(:porter_out_at_hobbiton).open?
  end

  test "open and resolved alerts can be listed separately" do
    assert_equal [inventory_alerts(:stout_out_at_hobbiton)], InventoryAlert.open.to_a
    assert_equal [inventory_alerts(:porter_out_at_hobbiton)], InventoryAlert.resolved.to_a
  end

  test "newest first orders by when the alert was raised, then by id" do
    same_time = new_alert(triggered_at: inventory_alerts(:porter_out_at_hobbiton).triggered_at).tap(&:save!)

    assert_equal [same_time, inventory_alerts(:porter_out_at_hobbiton), inventory_alerts(:stout_out_at_hobbiton)],
                 InventoryAlert.newest_first.to_a
  end

  test "alerts can be filtered by brand, and a blank brand leaves them unfiltered" do
    assert_equal [inventory_alerts(:stout_out_at_hobbiton)], InventoryAlert.for_brand(brands(:green_dragon).id).to_a
    assert_equal 2, InventoryAlert.for_brand("").count
    assert_equal 2, InventoryAlert.for_brand(nil).count
  end

  test "alerts can be filtered by status, and any other status leaves them unfiltered" do
    assert_equal [inventory_alerts(:stout_out_at_hobbiton)], InventoryAlert.with_status("open").to_a
    assert_equal [inventory_alerts(:porter_out_at_hobbiton)], InventoryAlert.with_status("resolved").to_a
    assert_equal 2, InventoryAlert.with_status("destroy_all").count
    assert_equal 2, InventoryAlert.with_status(nil).count
  end

  test "a resolved alert's streak runs from its first miss through the check that resolved it" do
    expected = %i[porter_sold_out_at_hobbiton porter_still_sold_out_at_hobbiton porter_restocked_at_hobbiton]

    assert_equal expected.map { inventory_checks(_1) }, inventory_alerts(:porter_out_at_hobbiton).streak_checks.to_a
  end

  test "an open alert's streak runs from its first miss through the latest check" do
    alert = inventory_alerts(:stout_out_at_hobbiton)
    later_miss = alert.store.inventory_checks.create!(product: alert.product, event_time: Time.utc(2024, 3, 9),
                                                      inventory_present: false)

    assert_equal [inventory_checks(:stout_sold_out_at_hobbiton), inventory_checks(:stout_still_sold_out_at_hobbiton), later_miss],
                 alert.streak_checks.to_a
  end

  test "a streak excludes same-day checks recorded before its first miss or after its resolution" do
    alert = inventory_alerts(:porter_out_at_hobbiton)
    after_resolution = alert.store.inventory_checks.create!(product: alert.product, event_time: alert.resolved_at,
                                                            inventory_present: false)
    before_start = InventoryCheck.new(store: alert.store, product: alert.product, event_time: alert.started_at,
                                      inventory_present: true)
    before_start.id = alert.streak_start_check_id - 1_000
    before_start.save!

    assert_not_includes alert.streak_checks, after_resolution
    assert_not_includes alert.streak_checks, before_start
    assert_equal 3, alert.streak_checks.count
  end

  test "brands, stores and products list their alerts" do
    assert_equal [inventory_alerts(:stout_out_at_hobbiton)], brands(:green_dragon).inventory_alerts.to_a
    assert_equal 2, stores(:hobbiton_bywater_road).inventory_alerts.count
    assert_equal [inventory_alerts(:porter_out_at_hobbiton)], products(:pony_porter).inventory_alerts.to_a
  end

  test "a streak needs at least two misses" do
    alert = new_alert(miss_count: 1)

    assert_not alert.valid?
    assert_equal ["must be greater than or equal to 2"], alert.errors[:miss_count]
  end

  test "an alert needs to know when its streak started and when it was raised" do
    alert = new_alert(started_at: nil, triggered_at: nil)

    assert_not alert.valid?
    assert_equal ["can't be blank"], alert.errors[:started_at]
    assert_equal ["can't be blank"], alert.errors[:triggered_at]
  end

  test "a resolved alert names the check that resolved it, and an open one has no resolution time" do
    resolved_without_check = new_alert(resolved_at: Time.utc(2024, 3, 9))
    check_without_time = new_alert(resolving_check: inventory_checks(:pale_ale_in_stock_at_bree))

    assert_not resolved_without_check.valid?
    assert_equal ["must be blank"], resolved_without_check.errors[:resolved_at]
    assert_not check_without_time.valid?
    assert_equal ["can't be blank"], check_without_time.errors[:resolved_at]
  end

  test "each streak has at most one alert" do
    alert = new_alert(streak_start_check: inventory_alerts(:stout_out_at_hobbiton).streak_start_check)

    assert_not alert.valid?
    assert_equal ["has already been taken"], alert.errors[:streak_start_check_id]
  end

  private

  # A valid alert whose streak no fixture alert uses.
  def new_alert(**attributes)
    InventoryAlert.new(brand: brands(:prancing_pony), store: stores(:bree_high_street), product: products(:pony_pale_ale),
                       streak_start_check: inventory_checks(:pale_ale_sold_out_at_bree),
                       triggering_check: inventory_checks(:pale_ale_sold_out_at_bree),
                       started_at: Time.utc(2024, 3, 2), triggered_at: Time.utc(2024, 3, 8), miss_count: 2, **attributes)
  end
end
