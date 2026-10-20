# Builds long check histories for pagination tests. One insert keeps a
# 51-row history cheap, and each day alternates in and out of stock.
module InventoryCheckHistory
  def record_daily_checks(store:, product:, days:, from:)
    rows = Array.new(days) do |offset|
      { store_id: store.id, product_id: product.id, event_time: (from + offset).to_time(:utc),
        inventory_present: offset.even? }
    end
    InventoryCheck.insert_all!(rows)
  end
end
