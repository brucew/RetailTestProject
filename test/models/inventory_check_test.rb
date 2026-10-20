require "test_helper"

class InventoryCheckTest < ActiveSupport::TestCase
  test "an inventory check links the product and store that were checked" do
    check = inventory_checks(:stout_sold_out_at_hobbiton)

    assert_equal products(:dragon_stout), check.product
    assert_equal stores(:hobbiton_bywater_road), check.store
  end

  test "an inventory check records whether inventory was present and when" do
    check = inventory_checks(:pale_ale_sold_out_at_bree)

    assert_equal false, check.inventory_present
    assert_equal Time.zone.parse("2024-03-02 09:00:00"), check.event_time
  end

  test "an inventory check is invalid without a product or store" do
    check = InventoryCheck.new(inventory_present: true, event_time: Time.current)

    assert_not check.valid?
    assert_equal ["must exist"], check.errors[:product]
    assert_equal ["must exist"], check.errors[:store]
  end

  test "an inventory check must say whether inventory was present" do
    check = new_check(inventory_present: nil)

    assert_not check.valid?
    assert_equal ["is not included in the list"], check.errors[:inventory_present]
  end

  test "an inventory check needs an event time" do
    check = new_check(event_time: nil)

    assert_not check.valid?
    assert_equal ["can't be blank"], check.errors[:event_time]
  end

  test "repeating an existing check exactly is invalid" do
    existing = inventory_checks(:pale_ale_sold_out_at_bree)
    check = new_check(event_time: existing.event_time, inventory_present: existing.inventory_present)

    assert_not check.valid?
    assert_equal ["is already recorded for this store, product and time"], check.errors[:inventory_present]
  end

  test "the opposite result at the same store, product and time is a different check" do
    existing = inventory_checks(:pale_ale_sold_out_at_bree)

    assert new_check(event_time: existing.event_time, inventory_present: true).valid?
  end

  test "the database rejects an exact repeat even when validations are skipped" do
    existing = inventory_checks(:pale_ale_sold_out_at_bree)

    assert_raises(ActiveRecord::RecordNotUnique) do
      new_check(event_time: existing.event_time, inventory_present: false).save(validate: false)
    end
  end

  test "exact duplicates are every copy of a repeated check except the earliest" do
    allow_duplicate_inventory_checks
    original = inventory_checks(:pale_ale_sold_out_at_bree)
    copies = Array.new(2) { original.dup.tap { |copy| copy.save!(validate: false) } }

    assert_equal copies.map(&:id).sort, InventoryCheck.exact_duplicates.ids.sort
  end

  test "there are no exact duplicates when every check is distinct" do
    assert_empty InventoryCheck.exact_duplicates
  end

  test "newest first orders by event time, then by id for checks on the same day" do
    same_day_later_row = new_check(event_time: inventory_checks(:pale_ale_sold_out_at_bree).event_time,
                                   inventory_present: true).tap(&:save!)

    assert_equal [same_day_later_row, inventory_checks(:pale_ale_sold_out_at_bree), inventory_checks(:pale_ale_in_stock_at_bree)],
                 products(:pony_pale_ale).inventory_checks.newest_first.to_a
  end

  private

  def new_check(**attributes)
    InventoryCheck.new(product: products(:pony_pale_ale), store: stores(:bree_high_street),
                       inventory_present: false, event_time: Time.zone.parse("2024-03-02 09:00:00"), **attributes)
  end
end
