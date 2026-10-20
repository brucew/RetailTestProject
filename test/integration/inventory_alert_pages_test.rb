require "test_helper"

class InventoryAlertPagesTest < ActionDispatch::IntegrationTest
  setup do
    @open_alert = inventory_alerts(:stout_out_at_hobbiton)
    @resolved_alert = inventory_alerts(:porter_out_at_hobbiton)
  end

  test "the alerts page lists each alert's dates, status, brand, product, store and misses" do
    get inventory_alerts_path

    assert_response :ok
    assert_select "h1", "Inventory alerts"
    assert_select ".summary dd", "2"
    assert_select "table.inventory-alerts tbody tr:first-child" do
      assert_select "td:nth-child(1) time[datetime=?]", "2024-03-06"
      assert_select ".status--resolved", "Resolved"
      assert_select "a[href=?]", brand_path(brands(:prancing_pony)), text: "Prancing Pony"
      assert_select "a[href=?]", product_path(products(:pony_porter)), text: "Pony Porter"
      assert_select "a[href=?]", store_path(stores(:hobbiton_bywater_road)), text: "12 Bywater Road, Hobbiton"
      assert_select "td.numeric", "2"
      assert_select "td:nth-child(7) time", "2024-03-05"
      assert_select "td:nth-child(8) time", "2024-03-07"
      assert_select "a[href=?]", inventory_alert_path(@resolved_alert), text: "Details"
    end
    assert_select "table.inventory-alerts tbody tr:last-child" do
      assert_select ".status--open", "Open"
      assert_select "td:nth-child(8)", ""
    end
    assert_no_match(/14:15/, response.body)
  end

  test "the alerts page lists the most recently raised alert first, and the later-recorded of a tie" do
    earlier = create_alert(product: products(:pony_pale_ale), store: stores(:bree_high_street),
                           started_on: Date.new(2025, 1, 1))
    later = create_alert(product: products(:pony_pale_ale), store: stores(:hobbiton_bywater_road),
                         started_on: Date.new(2025, 1, 1))

    get inventory_alerts_path

    assert_equal [later, earlier, @resolved_alert, @open_alert].map { |alert| inventory_alert_path(alert) },
                 css_select("table.inventory-alerts a:contains('Details')").pluck("href")
  end

  test "the alerts page shows 50 alerts to a page" do
    51.times do |index|
      create_alert(product: products(:pony_pale_ale), store: stores(:bree_high_street),
                   started_on: Date.new(2025, 1, 1) + (index * 3))
    end

    get inventory_alerts_path

    assert_select ".summary dd", "53"
    assert_select "table.inventory-alerts tbody tr", 50
    assert_select "nav.pagy a[href=?]", inventory_alerts_path(page: 2)

    get inventory_alerts_path(page: 2)

    assert_response :ok
    assert_select "table.inventory-alerts tbody tr", 3
    assert_equal [inventory_alert_path(@resolved_alert), inventory_alert_path(@open_alert)],
                 css_select("table.inventory-alerts a:contains('Details')").pluck("href").last(2)
  end

  test "the alerts page keeps its filters in the page links" do
    51.times do |index|
      create_alert(product: products(:pony_pale_ale), store: stores(:bree_high_street),
                   started_on: Date.new(2025, 1, 1) + (index * 3))
    end

    get inventory_alerts_path(brand_id: brands(:prancing_pony).id, status: "open")

    assert_select ".summary dd", "51"
    assert_select "nav.pagy a[href=?]",
                  "/inventory_alerts?brand_id=#{brands(:prancing_pony).id}&status=open&page=2"
  end

  test "the alerts page filters by brand" do
    get inventory_alerts_path(brand_id: brands(:green_dragon).id)

    assert_select "table.inventory-alerts tbody tr", 1
    assert_select "table.inventory-alerts a[href=?]", inventory_alert_path(@open_alert)
    assert_select "select#brand_id option[selected]", "Green Dragon"
  end

  test "the alerts page filters by status" do
    get inventory_alerts_path(status: "resolved")

    assert_select "table.inventory-alerts tbody tr", 1
    assert_select "table.inventory-alerts a[href=?]", inventory_alert_path(@resolved_alert)
    assert_select "select#status option[selected]", "Resolved"

    get inventory_alerts_path(status: "open")

    assert_select "table.inventory-alerts tbody tr", 1
    assert_select "table.inventory-alerts a[href=?]", inventory_alert_path(@open_alert)
  end

  test "the alerts page combines the brand and status filters" do
    get inventory_alerts_path(brand_id: brands(:prancing_pony).id, status: "resolved")

    assert_select "table.inventory-alerts tbody tr", 1
    assert_select "table.inventory-alerts a[href=?]", inventory_alert_path(@resolved_alert)

    get inventory_alerts_path(brand_id: brands(:prancing_pony).id, status: "open")

    assert_select "table.inventory-alerts", 0
    assert_select ".empty-state", "No alerts match these filters."
  end

  test "blank and unknown filter values list every alert" do
    [{ brand_id: "", status: "" }, { status: "snoozed" }].each do |filters|
      get inventory_alerts_path(filters)

      assert_response :ok
      assert_select "table.inventory-alerts tbody tr", 2
    end
    assert_select "select#brand_id option[selected]", 0
    assert_select "select#status option[selected]", 0
  end

  test "the filter form submits the brand and status as a GET to the alerts page" do
    get inventory_alerts_path

    assert_select "form.filters[method=get][action=?]", inventory_alerts_path do
      assert_equal ["All brands", "Green Dragon", "Prancing Pony"], css_select("select#brand_id option").map(&:text)
      assert_equal ["", "open", "resolved"], css_select("select#status option").pluck("value")
    end
  end

  test "an unknown brand matches no alerts" do
    get inventory_alerts_path(brand_id: 0)

    assert_response :ok
    assert_select ".empty-state", "No alerts match these filters."
  end

  test "the alerts page loads alerts and their brands, products and stores in a fixed number of queries" do
    3.times do |index|
      brand = Brand.create!(name: "Brand #{index}")
      product = brand.products.create!(name: "Product #{index}")
      store = Store.create!(address: "#{index} Long Lane, Tuckborough")
      create_alert(product:, store:, started_on: Date.new(2025, 1, 1))
    end

    # page count, page of alerts, their brands, stores, products, brands for the filter
    assert_max_queries(6) { get inventory_alerts_path }
    assert_select "table.inventory-alerts tbody tr", 5
  end

  test "a page past the last one is not found" do
    get inventory_alerts_path(page: 2)

    assert_response :not_found
  end

  test "a page that is not a positive number is a bad request" do
    get inventory_alerts_path(page: "abc")

    assert_response :bad_request
  end

  test "the alert page shows the alert's brand, product, store, dates and misses" do
    get inventory_alert_path(@resolved_alert)

    assert_response :ok
    assert_select "h1", "Pony Porter out of stock at 12 Bywater Road, Hobbiton"
    assert_select ".summary" do
      assert_select ".status--resolved", "Resolved"
      assert_select "a[href=?]", brand_path(brands(:prancing_pony)), text: "Prancing Pony"
      assert_select "a[href=?]", product_path(products(:pony_porter)), text: "Pony Porter"
      assert_select "a[href=?]", store_path(stores(:hobbiton_bywater_road)), text: "12 Bywater Road, Hobbiton"
      assert_select "dt", "Misses in a row"
      assert_select "dd:last-of-type", "2"
    end
    assert_equal %w[2024-03-05 2024-03-06 2024-03-07], css_select(".summary time").map(&:text)
    assert_select "a[href=?]", inventory_alerts_path(brand_id: brands(:prancing_pony).id),
                  text: "All alerts for Prancing Pony"
  end

  test "the alert page lists the streak's checks through the restock that resolved it" do
    get inventory_alert_path(@resolved_alert)

    assert_equal %w[2024-03-05 2024-03-06 2024-03-07], css_select("table.streak-checks tbody time").map(&:text)
    assert_equal ["Out of stock", "Out of stock", "In stock"],
                 css_select("table.streak-checks tbody .status").map(&:text)
  end

  test "an open alert's page has no resolved date and lists its misses so far" do
    get inventory_alert_path(@open_alert)

    assert_select ".summary .status--open", "Open"
    assert_select ".summary dt", text: "Resolved on", count: 0
    assert_equal %w[2024-03-03 2024-03-04], css_select("table.streak-checks tbody time").map(&:text)
  end

  test "the alert page loads in a fixed number of queries however long the streak" do
    product = products(:dragon_stout)
    store = stores(:hobbiton_bywater_road)
    5.times do |offset|
      store.inventory_checks.create!(product:, event_time: Time.utc(2024, 3, 5 + offset), inventory_present: false)
    end

    # alert, store, streak checks, brand, product
    assert_max_queries(5) { get inventory_alert_path(@open_alert) }
    assert_select "table.streak-checks tbody tr", 7
  end

  test "an unknown alert is not found" do
    get inventory_alert_path(id: 0)

    assert_response :not_found
  end

  private

  # A valid alert raised by two misses a day apart, so each call needs its own
  # store, product and start date (checks and streak starts are unique).
  def create_alert(product:, store:, started_on:)
    first_miss, second_miss = [started_on, started_on + 1].map do |date|
      store.inventory_checks.create!(product:, event_time: date.to_time(:utc), inventory_present: false)
    end
    InventoryAlert.create!(brand: product.brand, store:, product:, miss_count: 2,
                           streak_start_check: first_miss, started_at: first_miss.event_time,
                           triggering_check: second_miss, triggered_at: second_miss.event_time)
  end
end
