require "test_helper"

class StorePagesTest < ActionDispatch::IntegrationTest
  test "the store page shows each check's date and stock status" do
    get store_path(stores(:bree_high_street))

    assert_response :ok
    assert_select "td time[datetime=?]", "2024-03-02", text: "2024-03-02"
    assert_select "td .status--out-of-stock", text: "Out of stock"
    assert_no_match(/09:00/, response.body)
  end
end
