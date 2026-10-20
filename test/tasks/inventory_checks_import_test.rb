require "test_helper"
require "rake"
require "minitest/mock"

class InventoryChecksImportTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("inventory_checks:import")
  end

  test "importing an explicit path prints the file used and the result" do
    path = file_fixture("inventory_checks/valid.csv")

    output = capture_io { import_task.execute(Rake::TaskArguments.new([:path], [path.to_s])) }.first

    assert_equal <<~OUTPUT, output
      Importing inventory checks from #{path}
      Inventory checks: rows read=4 inserted=4 duplicates=0 rejected=0
    OUTPUT
  end

  test "rejected rows are listed after the result" do
    path = file_fixture("inventory_checks/unknown_store_and_product.csv")

    output = capture_io { import_task.execute(Rake::TaskArguments.new([:path], [path.to_s])) }.first

    assert_includes output, "Inventory checks: rows read=3 inserted=1 duplicates=0 rejected=2\n"
    assert_includes output, %(  rejected line 3: unknown store "99 Nowhere Lane, Mordor"\n)
    assert_includes output, %(  rejected line 4: unknown product "Orc Draught"\n)
  end

  test "without a path, inventory_checks.csv in the app root is imported even when tracking_events.csv exists" do
    in_app_root_with("inventory_checks.csv" => "valid.csv", "tracking_events.csv" => "unknown_store_and_product.csv") do |root|
      output = capture_io { import_task.execute(Rake::TaskArguments.new([:path], [])) }.first

      assert_includes output, "Importing inventory checks from #{root.join('inventory_checks.csv')}\n"
      assert_includes output, "rows read=4 inserted=4 duplicates=0 rejected=0"
    end
  end

  test "without a path or inventory_checks.csv, the legacy tracking_events.csv in the app root is imported" do
    in_app_root_with("tracking_events.csv" => "valid.csv") do |root|
      output = capture_io { import_task.execute(Rake::TaskArguments.new([:path], [])) }.first

      assert_includes output, "Importing inventory checks from #{root.join('tracking_events.csv')}\n"
      assert_includes output, "inserted=4"
    end
  end

  test "with no file to import, the task names the paths it looked for and exits with status 1" do
    in_app_root_with do |root|
      error = nil
      stderr = capture_io do
        error = assert_raises(SystemExit) { import_task.execute(Rake::TaskArguments.new([:path], [])) }
      end.last

      assert_equal 1, error.status
      assert_includes stderr, root.join("inventory_checks.csv").to_s
      assert_includes stderr, root.join("tracking_events.csv").to_s
    end
  end

  test "a file without the expected headers exits with status 1 and says which are missing" do
    path = file_fixture("inventory_checks/missing_date_header.csv")
    error = nil

    stderr = capture_io do
      error = assert_raises(SystemExit) { import_task.execute(Rake::TaskArguments.new([:path], [path.to_s])) }
    end.last

    assert_equal 1, error.status
    assert_equal "#{path} is missing required headers: Date\n", stderr
  end

  private

  def import_task
    Rake::Task["inventory_checks:import"]
  end

  # Builds a throwaway app root holding copies of fixture files, so the task's
  # default lookup never sees the real data file in the repository root.
  def in_app_root_with(copies = {}, &block)
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      copies.each { |name, fixture| FileUtils.cp(file_fixture("inventory_checks/#{fixture}"), root.join(name)) }
      Rails.stub(:root, root) { block.call(root) }
    end
  end
end
