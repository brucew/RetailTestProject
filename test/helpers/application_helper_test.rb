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

  test "shows a stored time as its date, without the time of day" do
    assert_dom_equal %(<time datetime="2024-03-01">2024-03-01</time>), utc_date_tag(Time.utc(2024, 3, 1, 14, 15))
  end

  test "keeps the stored UTC date when the app runs in a zone behind UTC" do
    Time.use_zone("Pacific Time (US & Canada)") do
      midnight_utc = Time.zone.parse("2024-03-01 00:00 UTC")

      assert_dom_equal %(<time datetime="2024-03-01">2024-03-01</time>), utc_date_tag(midnight_utc)
    end
  end
end
