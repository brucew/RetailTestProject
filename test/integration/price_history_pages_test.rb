require "test_helper"

class PriceHistoryPagesTest < ActionDispatch::IntegrationTest
  setup do
    @product = products(:pony_pale_ale)
  end

  test "the price history page names the product, links back to it and counts its price checks" do
    get product_price_checks_path(@product)

    assert_response :ok
    assert_select "h1", "Price history"
    assert_select ".summary a[href=?]", product_path(@product), text: "Pony Pale Ale"
    assert_select ".summary dd", "3"
  end

  test "the price history shows each check's date, price and store" do
    get product_price_checks_path(@product)

    assert_select "turbo-frame#price_history table.price-checks tbody tr:first-child" do
      assert_select "time[datetime=?]", "2024-03-02"
      assert_select "td.numeric", "$4.75"
      assert_select "a[href=?]", store_path(stores(:bree_high_street)), text: "1 High Street, Bree"
    end
  end

  test "the price history lists checks newest first, 50 to a page, with page links inside its frame" do
    record_daily_prices(store: stores(:hobbiton_bywater_road), days: 51, from: Date.new(2025, 1, 1))

    get product_price_checks_path(@product)

    assert_select "table.price-checks tbody tr", 50
    assert_select "table.price-checks tbody tr:first-child" do
      assert_select "time", "2025-02-20"
      assert_select "td.numeric", "$5.50"
    end
    assert_select "table.price-checks tbody tr:last-child time", "2025-01-02"
    assert_select "turbo-frame#price_history nav.pagy a[href=?]", product_price_checks_path(@product, page: 2)
  end

  test "the second page of the price history continues with older checks" do
    record_daily_prices(store: stores(:hobbiton_bywater_road), days: 51, from: Date.new(2025, 1, 1))

    get product_price_checks_path(@product, page: 2)

    assert_response :ok
    assert_equal %w[2025-01-01 2024-03-02 2024-03-01 2024-03-01],
                 css_select("table.price-checks tbody time").map(&:text)
  end

  test "same-day price checks list the later-recorded check first" do
    store = stores(:hobbiton_bywater_road)
    earlier = @product.price_checks.create!(store:, event_time: Time.utc(2025, 1, 1), price_cents: 520)
    later = @product.price_checks.create!(store:, event_time: Time.utc(2025, 1, 1), price_cents: 510)
    assert_operator later.id, :>, earlier.id

    get product_price_checks_path(@product)

    assert_equal %w[$5.10 $5.20], css_select("table.price-checks tbody td.numeric").first(2).map(&:text)
  end

  test "the price history loads its checks and their stores in a fixed number of queries" do
    6.times do |index|
      store = Store.create!(address: "#{index} Long Lane, Tuckborough")
      store.price_checks.create!(product: @product, event_time: Time.utc(2024, 4, 1), price_cents: 400 + index)
    end

    # product, price check count, page of price checks, their stores
    assert_max_queries(4) { get product_price_checks_path(@product) }
    assert_select "table.price-checks tbody tr", 9
  end

  test "a request from the product page's frame gets the frame without the site layout" do
    get product_price_checks_path(@product), headers: { "Turbo-Frame" => "price_history" }

    assert_response :ok
    assert_select "turbo-frame#price_history table.price-checks"
    assert_select "header.site-header", 0
  end

  test "a product without price checks says so instead of showing an empty table" do
    get product_price_checks_path(products(:pony_porter))

    assert_response :ok
    assert_select "turbo-frame#price_history .empty-state", /No price checks have been recorded/
    assert_select "table", 0
  end

  test "the price history of an unknown product is not found" do
    get product_price_checks_path(product_id: 0)

    assert_response :not_found
  end

  test "a price history page past the last one is not found" do
    get product_price_checks_path(@product, page: 2)

    assert_response :not_found
  end

  test "a price history page that is not a positive number is a bad request" do
    get product_price_checks_path(@product, page: "abc")

    assert_response :bad_request
  end

  private

  # One insert keeps a long price history cheap; each day costs a cent more.
  def record_daily_prices(store:, days:, from:)
    rows = Array.new(days) do |offset|
      { store_id: store.id, product_id: @product.id, event_time: (from + offset).to_time(:utc),
        price_cents: 500 + offset }
    end
    PriceCheck.insert_all!(rows)
  end
end
