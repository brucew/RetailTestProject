require "test_helper"

class StoreTest < ActiveSupport::TestCase
  test "a store lists the inventory checks recorded there" do
    assert_equal [inventory_checks(:porter_in_stock_at_hobbiton), inventory_checks(:stout_sold_out_at_hobbiton)],
                 stores(:hobbiton_bywater_road).inventory_checks.order(:event_time).to_a
  end
end
