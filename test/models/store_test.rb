require "test_helper"

class StoreTest < ActiveSupport::TestCase
  test "a store lists the tracking events recorded there" do
    assert_equal [tracking_events(:porter_in_stock_at_hobbiton), tracking_events(:stout_sold_out_at_hobbiton)],
                 stores(:hobbiton_bywater_road).tracking_events.order(:event_time).to_a
  end
end
