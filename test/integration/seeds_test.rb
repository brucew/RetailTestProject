require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeding adds the catalog alongside existing records" do
    capture_io { Rails.application.load_seed }

    assert_equal 2 + 45, Brand.count
    assert_equal 3 + 226, Product.count
    assert_equal 2 + 101, Store.count
    assert_equal "Weasleys’ Wizard Wheezes", Product.find_by!(name: "Extendable Ears").brand.name
  end

  test "seeding again changes nothing, even with tracking events referencing the catalog" do
    capture_io { Rails.application.load_seed }

    assert_no_difference [-> { Brand.count }, -> { Product.count }, -> { Store.count }, -> { TrackingEvent.count }] do
      capture_io { Rails.application.load_seed }
    end
  end
end
