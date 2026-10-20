require "test_helper"
require "rake"

class InventoryChecksMaintenanceTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("inventory_checks:remove_duplicates")
    allow_duplicate_inventory_checks
    @original = inventory_checks(:pale_ale_sold_out_at_bree)
    @copies = Array.new(2) { @original.dup.tap { |copy| copy.save!(validate: false) } }
  end

  test "a dry run reports the duplicates without deleting anything" do
    output = with_dry_run("1") { capture_io { remove_duplicates_task.execute }.first }

    assert_equal "Dry run: 2 exact duplicate inventory checks would be deleted.\n", output
    assert_equal 2, InventoryCheck.where(id: @copies).count
  end

  test "removing duplicates keeps the earliest copy and every distinct check" do
    distinct_check_ids = InventoryCheck.where.not(id: @copies).ids

    output = with_dry_run(nil) { capture_io { remove_duplicates_task.execute }.first }

    assert_equal "Deleted 2 exact duplicate inventory checks.\n", output
    assert_equal distinct_check_ids.sort, InventoryCheck.ids.sort
    assert InventoryCheck.exists?(@original.id)
  end

  private

  def remove_duplicates_task
    Rake::Task["inventory_checks:remove_duplicates"]
  end

  def with_dry_run(value)
    previous = ENV["DRY_RUN"]
    ENV["DRY_RUN"] = value
    yield
  ensure
    ENV["DRY_RUN"] = previous
  end
end
