require "test_helper"

class PriceCheckTest < ActiveSupport::TestCase
  test "a price check records the price of a product at a store on a day" do
    check = price_checks(:pale_ale_at_bree_march_second)

    assert_equal products(:pony_pale_ale), check.product
    assert_equal stores(:bree_high_street), check.store
    assert_equal 475, check.price_cents
    assert_equal Time.zone.parse("2024-03-02"), check.event_time
  end

  test "a price check is invalid without a product or store" do
    check = PriceCheck.new(price_cents: 100, event_time: Time.current)

    assert_not check.valid?
    assert_equal ["must exist"], check.errors[:product]
    assert_equal ["must exist"], check.errors[:store]
  end

  test "a price must be a whole number of cents" do
    assert_equal ["must be an integer"], errors_for(price_cents: 4.5)
    assert_equal ["is not a number"], errors_for(price_cents: nil)
  end

  test "a price cannot be negative, but can be zero" do
    assert_equal ["must be greater than or equal to 0"], errors_for(price_cents: -1)
    assert_empty errors_for(price_cents: 0)
  end

  test "a price check needs an event time" do
    check = new_check(event_time: nil)

    assert_not check.valid?
    assert_equal ["can't be blank"], check.errors[:event_time]
  end

  test "repeating an existing price check exactly is invalid" do
    existing = price_checks(:pale_ale_at_bree_march_second)

    check = new_check(event_time: existing.event_time, price_cents: existing.price_cents)

    assert_not check.valid?
    assert_equal ["is already recorded for this store, product and time"], check.errors[:price_cents]
  end

  test "a different price at the same store, product and time is a different check" do
    existing = price_checks(:pale_ale_at_bree_march_second)

    assert new_check(event_time: existing.event_time, price_cents: existing.price_cents + 25).valid?
  end

  test "newest first orders by event time, then by id for checks on the same day" do
    same_day_later_row = new_check(event_time: price_checks(:pale_ale_at_bree_march_second).event_time,
                                   price_cents: 499).tap(&:save!)

    assert_equal [same_day_later_row, price_checks(:pale_ale_at_bree_march_second), price_checks(:pale_ale_at_bree_march_first)],
                 stores(:bree_high_street).price_checks.newest_first.to_a
  end

  test "the latest price check is chosen for each store and product" do
    latest = PriceCheck.latest_per_store_and_product.order(:id).to_a

    assert_equal [price_checks(:pale_ale_at_bree_march_second), price_checks(:pale_ale_at_hobbiton_march_first),
                  price_checks(:stout_at_hobbiton_march_third)].sort_by(&:id), latest
  end

  test "the latest price on the same day is the later row" do
    same_day_later_row = new_check(event_time: price_checks(:pale_ale_at_bree_march_second).event_time,
                                   price_cents: 425).tap(&:save!)

    assert_includes PriceCheck.latest_per_store_and_product.to_a, same_day_later_row
    assert_not_includes PriceCheck.latest_per_store_and_product.to_a, price_checks(:pale_ale_at_bree_march_second)
  end

  test "latest prices can be scoped through an owner, then ordered and preloaded freely" do
    latest = products(:pony_pale_ale).price_checks.latest_per_store_and_product
                                     .includes(:store).order(price_cents: :desc).to_a

    assert_equal [price_checks(:pale_ale_at_bree_march_second), price_checks(:pale_ale_at_hobbiton_march_first)], latest
    assert latest.first.association(:store).loaded?
  end

  private

  def new_check(**attributes)
    PriceCheck.new(product: products(:pony_pale_ale), store: stores(:bree_high_street),
                   event_time: Time.zone.parse("2024-03-05"), price_cents: 500, **attributes)
  end

  def errors_for(price_cents:)
    new_check(price_cents:).tap(&:validate).errors[:price_cents]
  end
end
