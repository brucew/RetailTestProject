require "test_helper"

# Each test starts from empty tables: the fixture rows are deleted inside the
# test's transaction, so they come back for other tests on rollback and the
# seed counts can be asserted exactly rather than as deltas over fixtures.
class SeedsTest < ActiveSupport::TestCase
  setup do
    InventoryAlert.delete_all
    InventoryCheck.delete_all
    PriceCheck.delete_all
    Product.delete_all
    Brand.delete_all
    Store.delete_all
  end

  test "seeding an empty database creates every brand, product and store" do
    load_seeds

    assert_equal 45, Brand.count
    assert_equal 226, Product.count
    assert_equal 101, Store.count
  end

  test "seeding a second time changes nothing" do
    load_seeds
    snapshot = seeded_rows

    load_seeds

    assert_equal snapshot, seeded_rows
  end

  test "seeding succeeds when inventory checks already reference seeded rows" do
    load_seeds
    event = InventoryCheck.create!(product: Product.find_by!(name: "Chocolate Frogs"),
                                  store: Store.find_by!(address: "13 Honeydukes Corner, Hogsmeade Village"),
                                  inventory_present: true, event_time: Time.zone.parse("2024-03-01 09:00"))

    load_seeds

    assert_equal [event], InventoryCheck.all.to_a
    assert_equal 226, Product.count
  end

  test "seeding leaves an existing product under a different brand unchanged" do
    other_brand = Brand.create!(name: "Hogsmeade Imports")
    product = Product.create!(name: "Chocolate Frogs", brand: other_brand)

    load_seeds

    assert_equal other_brand, product.reload.brand
    assert_equal 1, Product.where(name: "Chocolate Frogs").count
    assert_equal 5, Brand.find_by!(name: "Honeydukes Sweetshop").products.count
  end

  private

  def load_seeds
    assert_output(/\ASeeded: /) { load Rails.root.join("db/seeds.rb") }
  end

  def seeded_rows
    {
      brands: Brand.order(:name).pluck(:id, :name),
      products: Product.order(:name).pluck(:id, :name, :brand_id),
      stores: Store.order(:address).pluck(:id, :address)
    }
  end
end
