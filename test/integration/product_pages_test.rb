require "test_helper"

class ProductPagesTest < ActionDispatch::IntegrationTest
  test "the product page shows each check's date and stock status" do
    get product_path(products(:pony_pale_ale))

    assert_response :ok
    assert_select "td time[datetime=?]", "2024-03-01", text: "2024-03-01"
    assert_select "td .status--in-stock", text: "In stock"
    assert_no_match(/09:00/, response.body)
  end
end
