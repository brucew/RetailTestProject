require "test_helper"
require "rake"
require "minitest/mock"

class PriceChecksGenerateSampleTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("price_checks:generate_sample")
  end

  test "writes the requested number of rows to the given path" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.csv")

      output = capture_io { generate_task.execute(Rake::TaskArguments.new(%i[path rows], [path, "25"])) }.first

      assert_equal "Wrote 25 price checks to #{path}\n", output
      assert_equal 26, File.readlines(path).size
    end
  end

  test "without arguments, writes 100,000 rows to price_checks.csv in the app root" do
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      generator = Minitest::Mock.new
      generator.expect(:write, 100_000, [root.join("price_checks.csv").to_s])

      output = Rails.stub(:root, root) do
        PriceChecks::SampleGenerator.stub(:new, ->(row_count:) { generator if row_count == 100_000 }) do
          capture_io { generate_task.execute(Rake::TaskArguments.new(%i[path rows], [])) }.first
        end
      end

      assert_equal "Wrote 100000 price checks to #{root.join('price_checks.csv')}\n", output
      generator.verify
    end
  end

  test "a row count that isn't a whole number exits with status 1" do
    error = nil
    stderr = capture_io do
      error = assert_raises(SystemExit) { generate_task.execute(Rake::TaskArguments.new(%i[path rows], ["unused.csv", "ten"])) }
    end.last

    assert_equal 1, error.status
    assert_includes stderr, '"ten"'
  end

  private

  def generate_task
    Rake::Task["price_checks:generate_sample"]
  end
end
