require "test_helper"

class StoreTest < ActiveSupport::TestCase
  test "a store lists the inventory checks recorded there" do
    assert_equal [inventory_checks(:porter_in_stock_at_hobbiton), inventory_checks(:stout_sold_out_at_hobbiton)],
                 stores(:hobbiton_bywater_road).inventory_checks.order(:event_time).to_a
  end

  test "a store needs an address" do
    store = Store.new(address: "")

    assert_not store.valid?
    assert_equal ["can't be blank"], store.errors[:address]
  end

  test "two stores cannot share an address, because the importer finds stores by address" do
    store = Store.new(address: stores(:bree_high_street).address)

    assert_not store.valid?
    assert_equal ["has already been taken"], store.errors[:address]
  end

  test "a store with inventory checks cannot be deleted" do
    store = stores(:bree_high_street)

    assert_not store.destroy
    assert Store.exists?(store.id)
  end

  test "a store with price checks cannot be deleted, even without inventory checks" do
    store = stores(:bree_high_street)
    store.inventory_checks.delete_all(:delete_all)

    assert_not store.destroy
    assert Store.exists?(store.id)
  end
end
