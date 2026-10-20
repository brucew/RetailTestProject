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

  test "the product page loads its brand, checks and stores in a fixed number of queries" do
    6.times do |index|
      store = Store.create!(address: "#{index} Long Lane, Tuckborough")
      store.inventory_checks.create!(product: @product, event_time: Time.utc(2024, 4, 1), inventory_present: true)
    end

    # product, its brand, page count, page of checks, their stores
    assert_max_queries(5) { get product_path(@product) }
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

  test "an unknown product is not found" do
    get product_path(id: 0)

    assert_response :not_found
  end

  test "a page past the last one is not found" do
    get product_path(@product, page: 2)

    assert_response :not_found
  end
end
