require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  attr_accessor :controller_name

  test "marks the link to the section being viewed as the current page" do
    self.controller_name = "stores"

    assert_dom_equal %(<a class="site-nav__link" aria-current="page" href="/stores">Stores</a>),
                     section_link_to("Stores", stores_path, "stores")
  end

  test "leaves links to other sections unmarked" do
    self.controller_name = "products"

    assert_dom_equal %(<a class="site-nav__link" href="/stores">Stores</a>),
                     section_link_to("Stores", stores_path, "stores")
  end
end
