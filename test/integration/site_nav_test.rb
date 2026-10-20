require "test_helper"

class SiteNavTest < ActionDispatch::IntegrationTest
  test "every section's pages share one navigation that marks the current section" do
    { stores_path => "Stores", store_path(stores(:bree_high_street)) => "Stores",
      products_path => "Products", product_path(products(:pony_pale_ale)) => "Products",
      brands_path => "Brands", brand_path(brands(:prancing_pony)) => "Brands" }.each do |path, section|
      get path

      assert_select "header nav.site-nav", 1
      assert_select "nav.site-nav a", 3
      assert_select "nav.site-nav a[aria-current=page]", text: section
    end
  end
end
