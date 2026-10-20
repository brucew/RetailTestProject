require "test_helper"

class ChecksHelperTest < ActionView::TestCase
  test "shows when a check happened as a date, without the time of day" do
    check = InventoryCheck.new(event_time: Time.utc(2024, 3, 1))

    assert_dom_equal %(<time datetime="2024-03-01">2024-03-01</time>), check_date_tag(check)
  end

  test "keeps the stored UTC date when the app runs in a zone behind UTC" do
    check = InventoryCheck.new(event_time: Time.utc(2024, 3, 1))

    Time.use_zone("Pacific Time (US & Canada)") do
      assert_dom_equal %(<time datetime="2024-03-01">2024-03-01</time>), check_date_tag(check)
    end
  end

  test "shows a price check's date the same way" do
    check = PriceCheck.new(event_time: Time.utc(2024, 12, 31))

    assert_dom_equal %(<time datetime="2024-12-31">2024-12-31</time>), check_date_tag(check)
  end
end
