require "test_helper"

class BrandPagesTest < ActionDispatch::IntegrationTest
  setup do
    @brand = brands(:prancing_pony)
  end

  test "the brands page lists brands by name with their product counts" do
    Brand.create!(name: "Golden Perch")

    get brands_path

    assert_response :ok
    assert_equal ["Golden Perch", "Green Dragon", "Prancing Pony"],
                 css_select("table.brands tbody tr td:first-child").map(&:text)
    assert_select "table.brands tbody tr:first-child td:nth-child(2)", "0"
    assert_select "table.brands tbody tr:last-child" do
      assert_select "a[href=?]", brand_path(@brand)
      assert_select "td:nth-child(2)", "2"
    end
  end

  test "the brands page counts every brand's products in one grouped query" do
    5.times { |index| Brand.create!(name: "Brand #{index}") }

    # brands, grouped product counts, grouped open-alert counts
    assert_max_queries(3) { get brands_path }
    assert_select "table.brands tbody tr", 7
  end

  test "the brand page lists the brand's products by name with their check counts" do
    @brand.products.create!(name: "Pony Bitter")

    get brand_path(@brand)

    assert_response :ok
    assert_select "h1", "Prancing Pony"
    assert_select ".summary dd:first-of-type", "3"
    assert_equal ["Pony Bitter", "Pony Pale Ale", "Pony Porter"],
                 css_select("table.products tbody tr td:first-child").map(&:text)
    assert_equal %w[0 2 4], css_select("table.products tbody td.numeric").map(&:text)
    assert_select "table.products a[href=?]", product_path(products(:pony_pale_ale))
  end

  test "the brand page lists only its own products" do
    get brand_path(@brand)

    assert_select "table.products a", text: "Dragon Stout", count: 0
  end

  test "the brand page loads its products and check counts in a fixed number of queries" do
    5.times do |index|
      product = @brand.products.create!(name: "Pony Special #{index}")
      product.inventory_checks.create!(store: stores(:bree_high_street), event_time: Time.utc(2024, 4, 1),
                                       inventory_present: true)
    end

    # brand, its products, grouped check counts, open-alert count
    assert_max_queries(4) { get brand_path(@brand) }
    assert_select "table.products tbody tr", 7
  end

  test "a brand without products says so instead of showing an empty table" do
    brand = Brand.create!(name: "Golden Perch")

    get brand_path(brand)

    assert_response :ok
    assert_select ".empty-state", /no products/
    assert_select "table", 0
  end

  test "the brands page links each brand's open-alert count to its open alerts" do
    get brands_path

    assert_select "table.brands tbody tr", 2
    assert_select "table.brands tbody tr:first-child td:nth-child(3)" do
      assert_select "a[href=?]", inventory_alerts_path(brand_id: brands(:green_dragon).id, status: "open"), text: "1"
    end
  end

  test "the brands page shows a brand without open alerts as a plain zero" do
    get brands_path

    # Prancing Pony's only alert is resolved.
    assert_select "table.brands tbody tr:last-child td:nth-child(3)", "0" do
      assert_select "a", 0
    end
  end

  test "the brand page links its open-alert count to its open alerts" do
    get brand_path(brands(:green_dragon))

    assert_select ".summary dt:nth-of-type(2)", "Open alerts"
    assert_select ".summary dd:nth-of-type(2) a[href=?]",
                  inventory_alerts_path(brand_id: brands(:green_dragon).id, status: "open"), text: "1"
  end

  test "the brand page shows no open alerts as a plain zero" do
    get brand_path(@brand)

    assert_select ".summary dd:nth-of-type(2)", "0" do
      assert_select "a", 0
    end
  end

  test "an unknown brand is not found" do
    get brand_path(id: 0)

    assert_response :not_found
  end
end
