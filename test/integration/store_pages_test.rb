require "test_helper"

class StorePagesTest < ActionDispatch::IntegrationTest
  setup do
    @store = stores(:bree_high_street)
  end

  test "the stores page lists every store by address with its check count" do
    get stores_path

    assert_response :ok
    assert_equal ["1 High Street, Bree", "12 Bywater Road, Hobbiton"],
                 css_select("table.stores tbody tr td:first-child").map(&:text)
    assert_select "table.stores tbody tr:first-child" do
      assert_select "a[href=?]", store_path(@store)
      assert_select "td.numeric", "2"
    end
  end

  test "the stores page sorts a newly added store by address and shows it with no checks" do
    Store.create!(address: "0 Ferry Lane, Bucklebury")

    get stores_path

    assert_select "table.stores tbody tr:first-child" do
      assert_select "td:first-child", "0 Ferry Lane, Bucklebury"
      assert_select "td.numeric", "0"
    end
  end

  test "the stores page counts every store's checks in one grouped query" do
    5.times { |index| Store.create!(address: "#{index} Long Lane, Tuckborough") }

    # stores, grouped check counts
    assert_max_queries(2) { get stores_path }
    assert_select "table.stores tbody tr", 7
  end

  test "the root path is the stores page" do
    get root_path

    assert_response :ok
    assert_select "h1", "Stores"
  end

  test "the store page shows the store and how many checks it has had" do
    get store_path(@store)

    assert_response :ok
    assert_select "h1", @store.address
    assert_select ".summary dd", "2"
  end

  test "the store page shows each check's date, stock status, product and brand" do
    get store_path(@store)

    assert_select "table.inventory-checks tbody tr:first-child" do
      assert_select "time[datetime=?]", "2024-03-02", text: "2024-03-02"
      assert_select ".status--out-of-stock", text: "Out of stock"
      assert_select "a[href=?]", product_path(products(:pony_pale_ale)), text: "Pony Pale Ale"
      assert_select "a[href=?]", brand_path(brands(:prancing_pony)), text: "Prancing Pony"
    end
    assert_no_match(/09:00/, response.body)
  end

  test "the store page loads its prices, checks, products and brands in a fixed number of queries" do
    6.times do |index|
      brand = Brand.create!(name: "Brand #{index}")
      product = brand.products.create!(name: "Product #{index}")
      product.inventory_checks.create!(store: @store, event_time: Time.utc(2024, 4, 1), inventory_present: true)
      product.price_checks.create!(store: @store, event_time: Time.utc(2024, 4, 1), price_cents: 300 + index)
    end

    # store, current prices with their products and brands,
    # page count, page of checks, their products, their brands
    assert_max_queries(6) { get store_path(@store) }
    assert_select "table.current-prices tbody tr", 7
    assert_select "table.inventory-checks tbody tr", 8
  end

  test "the store page lists checks newest first, 50 to a page" do
    record_daily_checks(store: @store, product: products(:pony_porter), days: 51, from: Date.new(2025, 1, 1))

    get store_path(@store)

    assert_select ".summary dd", "53"
    assert_select "table.inventory-checks tbody tr", 50
    assert_select "table.inventory-checks tbody tr:first-child time", "2025-02-20"
    assert_select "table.inventory-checks tbody tr:last-child time", "2025-01-02"
    assert_select "h2#inventory-checks"
    assert_select "nav.pagy a[href=?]", store_path(@store, page: 2, anchor: "inventory-checks")
  end

  test "the second page of the store page continues with older checks" do
    record_daily_checks(store: @store, product: products(:pony_porter), days: 51, from: Date.new(2025, 1, 1))

    get store_path(@store, page: 2)

    assert_response :ok
    assert_equal %w[2025-01-01 2024-03-02 2024-03-01], css_select("table.inventory-checks tbody time").map(&:text)
  end

  test "same-day checks at the store list the later-recorded check first" do
    earlier = @store.inventory_checks.create!(product: products(:pony_porter), event_time: Time.utc(2025, 1, 1),
                                              inventory_present: false)
    later = @store.inventory_checks.create!(product: products(:pony_porter), event_time: Time.utc(2025, 1, 1),
                                            inventory_present: true)
    assert_operator later.id, :>, earlier.id

    get store_path(@store)

    assert_select "table.inventory-checks tbody tr:nth-child(1) .status--in-stock"
    assert_select "table.inventory-checks tbody tr:nth-child(2) .status--out-of-stock"
  end

  test "a store without checks says so instead of showing an empty table" do
    store = Store.create!(address: "3 Market Square, Michel Delving")

    get store_path(store)

    assert_response :ok
    assert_select ".empty-state", /No inventory checks/
    assert_select "table", 0
  end

  test "the store page shows each product's latest price, brand and when it was checked" do
    get store_path(stores(:hobbiton_bywater_road))

    assert_select "table.current-prices tbody tr", 2
    assert_select "table.current-prices tbody tr:nth-child(1)" do
      assert_select "a[href=?]", product_path(products(:dragon_stout)), text: "Dragon Stout"
      assert_select "a[href=?]", brand_path(brands(:green_dragon)), text: "Green Dragon"
      assert_select "td.numeric", "$6.00"
      assert_select "time[datetime=?]", "2024-03-03"
    end
    assert_select "table.current-prices tbody tr:nth-child(2)" do
      assert_select "a[href=?]", product_path(products(:pony_pale_ale)), text: "Pony Pale Ale"
      assert_select "td.numeric", "$4.25"
      assert_select "time[datetime=?]", "2024-03-01"
    end
  end

  test "the store page orders current prices by product name" do
    brands(:green_dragon).products.create!(name: "Dragon Ale")
                         .price_checks.create!(store: @store, event_time: Time.utc(2024, 2, 1), price_cents: 399)
    products(:pony_porter).price_checks.create!(store: @store, event_time: Time.utc(2024, 2, 1), price_cents: 520)

    get store_path(@store)

    assert_equal ["Dragon Ale", "Pony Pale Ale", "Pony Porter"],
                 css_select("table.current-prices tbody td:first-child").map(&:text)
  end

  test "a product's current price is its newest check even when an older check was recorded later" do
    product = products(:pony_pale_ale)
    product.price_checks.create!(store: @store, event_time: Time.utc(2025, 2, 1), price_cents: 500)
    product.price_checks.create!(store: @store, event_time: Time.utc(2025, 1, 1), price_cents: 999)

    get store_path(@store)

    assert_select "table.current-prices tbody td.numeric", "$5.00"
  end

  test "a product's current price is the later-recorded of two checks on the same day" do
    product = products(:pony_pale_ale)
    earlier = product.price_checks.create!(store: @store, event_time: Time.utc(2025, 1, 1), price_cents: 520)
    later = product.price_checks.create!(store: @store, event_time: Time.utc(2025, 1, 1), price_cents: 510)
    assert_operator later.id, :>, earlier.id

    get store_path(@store)

    assert_select "table.current-prices tbody td.numeric", "$5.10"
  end

  test "a store without price checks says so instead of showing an empty price table" do
    store = Store.create!(address: "3 Market Square, Michel Delving")

    get store_path(store)

    assert_response :ok
    assert_select ".empty-state", /No prices have been recorded/
    assert_select "table.current-prices", 0
  end

  test "an unknown store is not found" do
    get store_path(id: 0)

    assert_response :not_found
  end

  test "a page past the last one is not found" do
    get store_path(@store, page: 2)

    assert_response :not_found
  end

  test "a page that is not a positive number is a bad request" do
    get store_path(@store, page: "abc")

    assert_response :bad_request
  end
end
