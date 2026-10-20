require "test_helper"
require "rake"

class TrackingEventsImportTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("tracking_events:import")
  end

  test "tracking_events:import runs the inventory check import, then the price check import, and nothing else" do
    task = Rake::Task["tracking_events:import"]

    assert_equal %w[inventory_checks:import price_checks:import], task.prerequisites
    assert_empty task.actions
  end
end
