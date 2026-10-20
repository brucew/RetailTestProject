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

ActiveRecord::Schema[7.1].define(version: 2026_10_20_230200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "brands", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_brands_on_name", unique: true
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

  add_foreign_key "inventory_checks", "products"
  add_foreign_key "inventory_checks", "stores"
  add_foreign_key "products", "brands"
end
