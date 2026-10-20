require "test_helper"

# The importer writes with insert_all, which skips model validations, so these
# rules must hold in the database itself.
class DatabaseConstraintsTest < ActiveSupport::TestCase
  test "catalog keys cannot be missing" do
    assert_raises(ActiveRecord::NotNullViolation) { Brand.new(name: nil).save(validate: false) }
    assert_raises(ActiveRecord::NotNullViolation) { Product.new(name: nil, brand: brands(:green_dragon)).save(validate: false) }
    assert_raises(ActiveRecord::NotNullViolation) { Store.new(address: nil).save(validate: false) }
  end

  test "catalog keys cannot repeat" do
    assert_raises(ActiveRecord::RecordNotUnique) { Brand.new(name: brands(:green_dragon).name).save(validate: false) }
    assert_raises(ActiveRecord::RecordNotUnique) do
      Product.new(name: products(:dragon_stout).name, brand: brands(:prancing_pony)).save(validate: false)
    end
    assert_raises(ActiveRecord::RecordNotUnique) { Store.new(address: stores(:bree_high_street).address).save(validate: false) }
  end

  test "an inventory check needs a result and a time" do
    check = inventory_checks(:pale_ale_in_stock_at_bree)

    assert_raises(ActiveRecord::NotNullViolation) { check.dup.tap { _1.inventory_present = nil }.save(validate: false) }
    assert_raises(ActiveRecord::NotNullViolation) { check.dup.tap { _1.event_time = nil }.save(validate: false) }
  end

  test "a price check needs a price and a time, and the price cannot be negative" do
    check = price_checks(:pale_ale_at_bree_march_first)

    assert_raises(ActiveRecord::NotNullViolation) { check.dup.tap { _1.price_cents = nil }.save(validate: false) }
    assert_raises(ActiveRecord::NotNullViolation) { check.dup.tap { _1.event_time = nil }.save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { check.dup.tap { _1.price_cents = -1 }.save(validate: false) }
  end

  test "an exact repeat of a price check is rejected" do
    assert_raises(ActiveRecord::RecordNotUnique) { price_checks(:pale_ale_at_bree_march_first).dup.save(validate: false) }
  end

  test "an alert needs a streak of at least two misses and a start, trigger and time" do
    error = assert_raises(ActiveRecord::StatementInvalid) { unsaved_alert(miss_count: 1).save(validate: false) }
    assert_match "inventory_alerts_streak_has_two_misses", error.message

    %i[brand_id store_id product_id triggering_check_id started_at triggered_at miss_count].each do |column|
      assert_raises(ActiveRecord::NotNullViolation, column.to_s) { unsaved_alert(column => nil).save(validate: false) }
    end
  end

  test "an alert is resolved by a check and a time together, or by neither" do
    [{ resolved_at: Time.current }, { resolving_check: inventory_checks(:pale_ale_in_stock_at_bree) }].each do |half|
      error = assert_raises(ActiveRecord::StatementInvalid) { unsaved_alert(**half).save(validate: false) }
      assert_match "inventory_alerts_resolved_with_a_check", error.message
    end
  end

  test "the alert used to probe constraints is otherwise valid" do
    assert unsaved_alert.save(validate: false)
  end

  test "a streak has at most one alert" do
    assert_raises(ActiveRecord::RecordNotUnique) { inventory_alerts(:stout_out_at_hobbiton).dup.save(validate: false) }
  end

  private

  # A copy of an open fixture alert for a streak no other alert uses, so only
  # the constraint under test can reject it.
  def unsaved_alert(**attributes)
    inventory_alerts(:stout_out_at_hobbiton).dup.tap do |alert|
      alert.streak_start_check = inventory_checks(:pale_ale_sold_out_at_bree)
      alert.assign_attributes(attributes)
    end
  end
end
