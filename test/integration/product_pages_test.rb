require "test_helper"

class ProductPagesTest < ActionDispatch::IntegrationTest
  setup do
    @product = products(:pony_pale_ale)
  end

  test "the products page lists products by name with their brand and check count" do
    brands(:green_dragon).products.create!(name: "Dragon Ale")

    get products_path

    assert_response :ok
    assert_equal ["Dragon Ale", "Dragon Stout", "Pony Pale Ale", "Pony Porter"],
                 css_select("table.products tbody tr td:first-child").map(&:text)
    assert_select "table.products tbody tr:first-child" do
      assert_select "a[href=?]", brand_path(brands(:green_dragon)), text: "Green Dragon"
      assert_select "td.numeric", "0"
    end
    assert_select "table.products tbody tr:nth-child(3)" do
      assert_select "a[href=?]", product_path(@product), text: "Pony Pale Ale"
      assert_select "td.numeric", "2"
    end
  end

  test "the products page loads brands and check counts in a fixed number of queries" do
    5.times do |index|
      brand = Brand.create!(name: "Brand #{index}")
      brand.products.create!(name: "Product #{index}")
    end

    # products, their brands, grouped check counts
    assert_max_queries(3) { get products_path }
    assert_select "table.products tbody tr", 8
  end

  test "the product page shows the product, its brand and how many checks it has had" do
    get product_path(@product)

    assert_response :ok
    assert_select "h1", @product.name
    assert_select ".summary a[href=?]", brand_path(brands(:prancing_pony)), text: "Prancing Pony"
    assert_select ".summary dd", "2"
  end

  test "the product page shows each check's date, stock status and store" do
    get product_path(@product)

    assert_select "table.inventory-checks tbody tr:last-child" do
      assert_select "time[datetime=?]", "2024-03-01", text: "2024-03-01"
      assert_select ".status--in-stock", text: "In stock"
      assert_select "a[href=?]", store_path(stores(:bree_high_street)), text: "1 High Street, Bree"
    end
    assert_no_match(/09:00/, response.body)
  end

  test "the product page loads its brand, prices, checks and stores in a fixed number of queries" do
    6.times do |index|
      store = Store.create!(address: "#{index} Long Lane, Tuckborough")
      store.inventory_checks.create!(product: @product, event_time: Time.utc(2024, 4, 1), inventory_present: true)
      store.price_checks.create!(product: @product, event_time: Time.utc(2024, 4, 1), price_cents: 400 + index)
    end

    # product, its brand, current prices with their stores,
    # inventory check count, page of inventory checks, their stores,
    # price check count, page of price checks, their stores
    assert_max_queries(9) { get product_path(@product) }
    assert_select "table.current-prices tbody tr", 8
    assert_select "table.price-checks tbody tr", 9
    assert_select "table.inventory-checks tbody tr", 8
  end

  test "the product page lists checks newest first, 50 to a page" do
    record_daily_checks(store: stores(:hobbiton_bywater_road), product: @product, days: 51, from: Date.new(2025, 1, 1))

    get product_path(@product)

    assert_select ".summary dd", "53"
    assert_select "table.inventory-checks tbody tr", 50
    assert_select "table.inventory-checks tbody tr:first-child time", "2025-02-20"
    assert_select "table.inventory-checks tbody tr:last-child time", "2025-01-02"
    assert_select "h2#inventory-checks"
    assert_select "nav.pagy a[href=?]", product_path(@product, page: 2, anchor: "inventory-checks")
  end

  test "the second page of the product page continues with older checks" do
    record_daily_checks(store: stores(:hobbiton_bywater_road), product: @product, days: 51, from: Date.new(2025, 1, 1))

    get product_path(@product, page: 2)

    assert_response :ok
    assert_equal %w[2025-01-01 2024-03-02 2024-03-01], css_select("table.inventory-checks tbody time").map(&:text)
  end

  test "same-day checks of the product list the later-recorded check first" do
    earlier = @product.inventory_checks.create!(store: stores(:hobbiton_bywater_road), event_time: Time.utc(2025, 1, 1),
                                                inventory_present: false)
    later = @product.inventory_checks.create!(store: stores(:hobbiton_bywater_road), event_time: Time.utc(2025, 1, 1),
                                              inventory_present: true)
    assert_operator later.id, :>, earlier.id

    get product_path(@product)

    assert_select "table.inventory-checks tbody tr:nth-child(1) .status--in-stock"
    assert_select "table.inventory-checks tbody tr:nth-child(2) .status--out-of-stock"
  end

  test "a product without checks says so instead of showing an empty table" do
    product = brands(:green_dragon).products.create!(name: "Dragon Mild")

    get product_path(product)

    assert_response :ok
    assert_select ".empty-state", /No inventory checks/
    assert_select "table", 0
  end

  test "the product page shows each store's latest price and when it was checked" do
    get product_path(@product)

    assert_select "table.current-prices tbody tr", 2
    assert_select "table.current-prices tbody tr:nth-child(1)" do
      assert_select "a[href=?]", store_path(stores(:bree_high_street)), text: "1 High Street, Bree"
      assert_select "td.numeric", "$4.75"
      assert_select "time[datetime=?]", "2024-03-02"
    end
    assert_select "table.current-prices tbody tr:nth-child(2)" do
      assert_select "a[href=?]", store_path(stores(:hobbiton_bywater_road)), text: "12 Bywater Road, Hobbiton"
      assert_select "td.numeric", "$4.25"
      assert_select "time[datetime=?]", "2024-03-01"
    end
  end

  test "the product page orders current prices by store address" do
    Store.create!(address: "0 Ferry Lane, Bucklebury")
         .price_checks.create!(product: @product, event_time: Time.utc(2024, 2, 1), price_cents: 399)

    get product_path(@product)

    assert_equal ["0 Ferry Lane, Bucklebury", "1 High Street, Bree", "12 Bywater Road, Hobbiton"],
                 css_select("table.current-prices tbody td:first-child").map(&:text)
  end

  test "a store's current price is its newest check even when an older check was recorded later" do
    store = stores(:hobbiton_bywater_road)
    @product.price_checks.create!(store:, event_time: Time.utc(2025, 2, 1), price_cents: 500)
    @product.price_checks.create!(store:, event_time: Time.utc(2025, 1, 1), price_cents: 999)

    get product_path(@product)

    assert_select "table.current-prices tbody tr:nth-child(2) td.numeric", "$5.00"
  end

  test "a store's current price is the later-recorded of two checks on the same day" do
    store = stores(:hobbiton_bywater_road)
    earlier = @product.price_checks.create!(store:, event_time: Time.utc(2025, 1, 1), price_cents: 520)
    later = @product.price_checks.create!(store:, event_time: Time.utc(2025, 1, 1), price_cents: 510)
    assert_operator later.id, :>, earlier.id

    get product_path(@product)

    assert_select "table.current-prices tbody tr:nth-child(2) td.numeric", "$5.10"
  end

  test "a product without price checks says so instead of showing an empty price table" do
    get product_path(products(:pony_porter))

    assert_response :ok
    assert_select ".empty-state", /No prices have been recorded/
    assert_select "table.current-prices", 0
  end

  test "the product page lists price checks newest first, 50 to a page" do
    record_daily_prices(store: stores(:hobbiton_bywater_road), days: 51, from: Date.new(2025, 1, 1))

    get product_path(@product)

    assert_select "table.price-checks tbody tr", 50
    assert_select "table.price-checks tbody tr:first-child" do
      assert_select "time", "2025-02-20"
      assert_select "td.numeric", "$5.50"
      assert_select "a[href=?]", store_path(stores(:hobbiton_bywater_road)), text: "12 Bywater Road, Hobbiton"
    end
    assert_select "table.price-checks tbody tr:last-child time", "2025-01-02"
    assert_select "h2#price-history"
    assert_select "nav.pagy a[href=?]", product_path(@product, price_page: 2, anchor: "price-history")
  end

  test "the second page of price history continues with older price checks" do
    record_daily_prices(store: stores(:hobbiton_bywater_road), days: 51, from: Date.new(2025, 1, 1))

    get product_path(@product, price_page: 2)

    assert_response :ok
    assert_equal %w[2025-01-01 2024-03-02 2024-03-01 2024-03-01],
                 css_select("table.price-checks tbody time").map(&:text)
  end

  test "paging through price history leaves the inventory list on its own page" do
    record_daily_prices(store: stores(:hobbiton_bywater_road), days: 51, from: Date.new(2025, 1, 1))
    record_daily_checks(store: stores(:hobbiton_bywater_road), product: @product, days: 51, from: Date.new(2025, 1, 1))

    get product_path(@product, price_page: 2)

    assert_select "table.price-checks tbody tr:first-child time", "2025-01-01"
    assert_select "table.inventory-checks tbody tr:first-child time", "2025-02-20"
    assert_select "nav.pagy a[href=?]", "#{product_path(@product)}?price_page=2&page=2#inventory-checks"
  end

  test "paging through inventory checks leaves the price history on its own page" do
    record_daily_prices(store: stores(:hobbiton_bywater_road), days: 51, from: Date.new(2025, 1, 1))
    record_daily_checks(store: stores(:hobbiton_bywater_road), product: @product, days: 51, from: Date.new(2025, 1, 1))

    get product_path(@product, page: 2)

    assert_select "table.inventory-checks tbody tr:first-child time", "2025-01-01"
    assert_select "table.price-checks tbody tr:first-child time", "2025-02-20"
    assert_select "nav.pagy a[href=?]", "#{product_path(@product)}?page=2&price_page=2#price-history"
  end

  test "same-day price checks list the later-recorded check first" do
    store = stores(:hobbiton_bywater_road)
    earlier = @product.price_checks.create!(store:, event_time: Time.utc(2025, 1, 1), price_cents: 520)
    later = @product.price_checks.create!(store:, event_time: Time.utc(2025, 1, 1), price_cents: 510)
    assert_operator later.id, :>, earlier.id

    get product_path(@product)

    assert_equal %w[$5.10 $5.20], css_select("table.price-checks tbody tr td.numeric").first(2).map(&:text)
  end

  test "a product without price checks says so instead of showing an empty price history" do
    get product_path(products(:pony_porter))

    assert_select ".empty-state", /No price checks have been recorded/
    assert_select "table.price-checks", 0
  end

  test "a price history page past the last one is not found" do
    get product_path(@product, price_page: 2)

    assert_response :not_found
  end

  test "a price history page that is not a positive number is a bad request" do
    get product_path(@product, price_page: "abc")

    assert_response :bad_request
  end

  test "an unknown product is not found" do
    get product_path(id: 0)

    assert_response :not_found
  end

  test "a page past the last one is not found" do
    get product_path(@product, page: 2)

    assert_response :not_found
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
