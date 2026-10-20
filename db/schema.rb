# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_10_21_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "brands", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_brands_on_name", unique: true
  end

  create_table "inventory_alerts", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "store_id", null: false
    t.bigint "product_id", null: false
    t.bigint "streak_start_check_id", null: false
    t.bigint "triggering_check_id", null: false
    t.bigint "resolving_check_id"
    t.datetime "started_at", null: false
    t.datetime "triggered_at", null: false
    t.datetime "resolved_at"
    t.integer "miss_count", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "triggered_at"], name: "index_inventory_alerts_on_brand_id_and_triggered_at"
    t.index ["store_id", "product_id"], name: "index_inventory_alerts_on_store_id_and_product_id"
    t.index ["streak_start_check_id"], name: "index_inventory_alerts_on_streak_start_check_id", unique: true
    t.check_constraint "(resolved_at IS NULL) = (resolving_check_id IS NULL)", name: "inventory_alerts_resolved_with_a_check"
    t.check_constraint "miss_count >= 2", name: "inventory_alerts_streak_has_two_misses"
  end

  create_table "inventory_checks", force: :cascade do |t|
    t.boolean "inventory_present", null: false
    t.bigint "product_id", null: false
    t.bigint "store_id", null: false
    t.datetime "event_time", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "event_time"], name: "index_inventory_checks_on_product_id_and_event_time"
    t.index ["store_id", "event_time"], name: "index_inventory_checks_on_store_id_and_event_time"
    t.index ["store_id", "product_id", "event_time", "inventory_present"], name: "index_inventory_checks_on_store_product_time_presence", unique: true
  end

  create_table "price_checks", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "product_id", null: false
    t.datetime "event_time", null: false
    t.bigint "price_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "event_time"], name: "index_price_checks_on_product_id_and_event_time"
    t.index ["store_id", "product_id", "event_time", "price_cents"], name: "index_price_checks_on_store_product_time_price", unique: true
    t.check_constraint "price_cents >= 0", name: "price_checks_price_cents_not_negative"
  end

  create_table "products", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "brand_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_products_on_brand_id"
    t.index ["name"], name: "index_products_on_name", unique: true
  end

  create_table "stores", force: :cascade do |t|
    t.string "address", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["address"], name: "index_stores_on_address", unique: true
  end

  add_foreign_key "inventory_alerts", "brands", name: "fk_inventory_alerts_brand"
  add_foreign_key "inventory_alerts", "inventory_checks", column: "resolving_check_id", name: "fk_inventory_alerts_resolving_check"
  add_foreign_key "inventory_alerts", "inventory_checks", column: "streak_start_check_id", name: "fk_inventory_alerts_streak_start_check"
  add_foreign_key "inventory_alerts", "inventory_checks", column: "triggering_check_id", name: "fk_inventory_alerts_triggering_check"
  add_foreign_key "inventory_alerts", "products", name: "fk_inventory_alerts_product"
  add_foreign_key "inventory_alerts", "stores", name: "fk_inventory_alerts_store"
  add_foreign_key "inventory_checks", "products"
  add_foreign_key "inventory_checks", "stores"
  add_foreign_key "price_checks", "products", name: "fk_price_checks_product"
  add_foreign_key "price_checks", "stores", name: "fk_price_checks_store"
  add_foreign_key "products", "brands"
end
