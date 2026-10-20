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
end
