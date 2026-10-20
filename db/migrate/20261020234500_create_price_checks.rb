class CreatePriceChecks < ActiveRecord::Migration[7.1]
  # A price check is independent of an inventory check: either can happen
  # without the other, so each has its own table with non-nullable columns.
  def change
    create_table :price_checks do |t|
      t.references :store, null: false, index: false, foreign_key: { name: "fk_price_checks_store" }
      t.references :product, null: false, index: false, foreign_key: { name: "fk_price_checks_product" }
      t.datetime :event_time, null: false
      # Integer cents in a single currency (USD): exact arithmetic, no floats.
      t.bigint :price_cents, null: false
      t.timestamps

      t.check_constraint "price_cents >= 0", name: "price_checks_price_cents_not_negative"
    end

    # Rejects exact duplicate rows, like inventory checks, which makes
    # re-imports idempotent. Different prices on the same day are all kept.
    # Also serves "latest price per product" for a store.
    add_index :price_checks, %i[store_id product_id event_time price_cents],
              unique: true, name: "index_price_checks_on_store_product_time_price"
    # Product page: price history and latest price per store.
    add_index :price_checks, %i[product_id event_time]
  end
end
