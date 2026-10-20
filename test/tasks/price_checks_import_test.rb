require "test_helper"
require "rake"
require "minitest/mock"

class PriceChecksImportTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("price_checks:import")
  end

  test "importing an explicit path prints the file used and the result" do
    path = file_fixture("price_checks/valid.csv")

    output = capture_io { import_task.execute(Rake::TaskArguments.new([:path], [path.to_s])) }.first

    assert_equal <<~OUTPUT, output
      Importing price checks from #{path}
      Price checks: rows read=4 inserted=4 duplicates=0 rejected=0
    OUTPUT
  end

  test "rejected rows are listed after the result" do
    path = file_fixture("price_checks/invalid_prices.csv")

    output = capture_io { import_task.execute(Rake::TaskArguments.new([:path], [path.to_s])) }.first

    assert_includes output, "Price checks: rows read=7 inserted=1 duplicates=0 rejected=6\n"
    assert_includes output, %(  rejected line 4: invalid price "$5" (expected dollars such as 4 or 4.99)\n)
  end

  test "without a path, price_checks.csv in the app root is imported" do
    in_app_root_with("price_checks.csv" => "valid.csv") do |root|
      output = capture_io { import_task.execute(Rake::TaskArguments.new([:path], [])) }.first

      assert_includes output, "Importing price checks from #{root.join('price_checks.csv')}\n"
      assert_includes output, "rows read=4 inserted=4 duplicates=0 rejected=0"
    end
  end

  test "with no file to import, the task names the path it looked for and exits with status 1" do
    in_app_root_with do |root|
      error = nil
      stderr = capture_io do
        error = assert_raises(SystemExit) { import_task.execute(Rake::TaskArguments.new([:path], [])) }
      end.last

      assert_equal 1, error.status
      assert_equal "No price checks CSV found. Looked for:\n  #{root.join('price_checks.csv')}\n", stderr
    end
  end

  test "a file without the expected headers exits with status 1 and says which are missing" do
    path = file_fixture("price_checks/missing_price_header.csv")
    error = nil

    stderr = capture_io do
      error = assert_raises(SystemExit) { import_task.execute(Rake::TaskArguments.new([:path], [path.to_s])) }
    end.last

    assert_equal 1, error.status
    assert_equal "#{path} is missing required headers: Price\n", stderr
  end

  private

  def import_task
    Rake::Task["price_checks:import"]
  end

  # A throwaway app root, so the default lookup never sees the real data file.
  def in_app_root_with(copies = {}, &block)
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      copies.each { |name, fixture| FileUtils.cp(file_fixture("price_checks/#{fixture}"), root.join(name)) }
      Rails.stub(:root, root) { block.call(root) }
    end
  end
end
