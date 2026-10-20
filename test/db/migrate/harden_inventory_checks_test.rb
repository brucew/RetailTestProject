require "test_helper"
require Rails.root.join("db/migrate/20261020230200_harden_inventory_checks")

class HardenInventoryChecksTest < ActiveSupport::TestCase
  test "migrating aborts with cleanup instructions instead of deleting duplicates" do
    allow_duplicate_inventory_checks
    inventory_checks(:pale_ale_sold_out_at_bree).dup.save!(validate: false)

    error = assert_raises(ActiveRecord::MigrationError) do
      ActiveRecord::Migration.suppress_messages { HardenInventoryChecks.new.migrate(:up) }
    end

    assert_match "inventory_checks has 1 exact duplicate rows", error.message
    assert_match "DRY_RUN=1 bin/rails inventory_checks:remove_duplicates", error.message
    assert_equal 2, InventoryCheck.where(event_time: inventory_checks(:pale_ale_sold_out_at_bree).event_time).count
  end
end
