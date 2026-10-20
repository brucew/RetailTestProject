class HardenInventoryChecks < ActiveRecord::Migration[7.1]
  # A repeated row (same store, product, event time and presence) is a
  # duplicate submission, not a second check. The unique index enforces that
  # and lets the importer skip repeats, which makes re-imports idempotent.
  def change
    reversible { |direction| direction.up { ensure_no_exact_duplicates } }

    # No default: a missing value must fail loudly rather than silently
    # record a stockout.
    change_column_null :inventory_checks, :inventory_present, false
    change_column_null :inventory_checks, :event_time, false

    add_index :inventory_checks, %i[store_id product_id event_time inventory_present],
              unique: true, name: "index_inventory_checks_on_store_product_time_presence"
    add_index :inventory_checks, %i[store_id event_time]
    add_index :inventory_checks, %i[product_id event_time]

    # Covered by the leading columns of the composite indexes above.
    remove_index :inventory_checks, :store_id
    remove_index :inventory_checks, :product_id
  end

  private

  # Migrations never delete data. Removing duplicates is a deliberate,
  # separate step the operator runs and can preview.
  def ensure_no_exact_duplicates
    duplicate_count = select_value(<<~SQL)
      SELECT COUNT(*) - COUNT(DISTINCT (store_id, product_id, event_time, inventory_present))
      FROM inventory_checks
    SQL
    return if duplicate_count.zero?

    raise ActiveRecord::MigrationError, <<~MESSAGE
      inventory_checks has #{duplicate_count} exact duplicate rows, so the unique index cannot be added.
      Preview them:  DRY_RUN=1 bin/rails inventory_checks:remove_duplicates
      Remove them:   bin/rails inventory_checks:remove_duplicates   (keeps the earliest copy of each)
      Then re-run:   bin/rails db:migrate
    MESSAGE
  end
end
