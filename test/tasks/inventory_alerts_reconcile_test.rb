require "test_helper"
require "rake"

class InventoryAlertsReconcileTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("inventory_alerts:reconcile")
  end

  test "reconciling rebuilds every pair's alerts and prints what changed" do
    inventory_alerts(:stout_out_at_hobbiton).update!(miss_count: 7)
    inventory_alerts(:porter_out_at_hobbiton).destroy!

    output = capture_io { Rake::Task["inventory_alerts:reconcile"].execute }.first

    assert_equal "Reconciled every store and product: alerts created=1 updated=1 deleted=0\n", output
    assert_equal 2, inventory_alerts(:stout_out_at_hobbiton).reload.miss_count
  end

  test "reconciling alerts that are already up to date changes nothing" do
    output = capture_io { Rake::Task["inventory_alerts:reconcile"].execute }.first

    assert_equal "Reconciled every store and product: alerts created=0 updated=0 deleted=0\n", output
  end
end
