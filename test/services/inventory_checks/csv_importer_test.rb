require "test_helper"
require "csv"
require "minitest/mock"

class InventoryChecks::CsvImporterTest < ActiveSupport::TestCase
  setup do
    @log = StringIO.new
  end

  test "importing a valid file stores every row and reports the counts" do
    result = import("valid.csv")

    assert_equal [4, 4, 0, 0], [result.rows_read, result.inserted, result.duplicates, result.rejected]
    assert_empty result.rejection_samples
  end

  test "rows are written in batches, one INSERT per batch" do
    inserts = []
    counter = ->(*, payload) { inserts << payload[:sql] if payload[:sql].start_with?("INSERT") }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { import("valid.csv", batch_size: 3) }

    assert_equal 2, inserts.size
  end

  test "imported checks keep the store, product, day and presence from the file" do
    import("valid.csv")

    assert_equal [
      ["1 High Street, Bree", "Pony Pale Ale", Time.zone.local(2025, 1, 2), true],
      ["1 High Street, Bree", "Pony Pale Ale", Time.zone.local(2025, 1, 3), false],
      ["12 Bywater Road, Hobbiton", "Dragon Stout", Time.zone.local(2025, 1, 2), true],
      ["12 Bywater Road, Hobbiton", "Pony Porter", Time.zone.local(2025, 1, 4), false]
    ], imported_checks
  end

  test "rows naming an unknown store or product are rejected with the line and name" do
    result = import("unknown_store_and_product.csv")

    assert_equal [rejection(3, 'unknown store "99 Nowhere Lane, Mordor"'),
                  rejection(4, 'unknown product "Orc Draught"')], result.rejection_samples
  end

  test "rows with a date that isn't a real YYYY-MM-DD day are rejected" do
    result = import("invalid_dates.csv")

    assert_equal [rejection(2, 'invalid date "02/01/2025" (expected YYYY-MM-DD)'),
                  rejection(3, "invalid date nil (expected YYYY-MM-DD)"),
                  rejection(4, 'invalid date "2025-02-30" (expected YYYY-MM-DD)')], result.rejection_samples
  end

  test "rows whose inventory presence isn't True or False are rejected, never read as out of stock" do
    result = assert_no_difference("InventoryCheck.count") { import("invalid_inventory_present.csv") }

    assert_equal [rejection(2, 'invalid inventory present "yes" (expected True or False)'),
                  rejection(3, "invalid inventory present nil (expected True or False)"),
                  rejection(4, 'invalid inventory present "1" (expected True or False)')], result.rejection_samples
  end

  test "rejected rows are counted while the valid rows in the same file are imported" do
    result = import("rejections.csv")

    assert_equal [9, 1, 0, 8], [result.rows_read, result.inserted, result.duplicates, result.rejected]
    assert_equal [["1 High Street, Bree", "Pony Pale Ale", Time.zone.local(2025, 1, 2), true]], imported_checks
  end

  test "only the first few rejections are kept as samples, and each is logged" do
    result = import("rejections.csv")

    assert_equal [3, 4, 5, 6, 7], result.rejection_samples.map(&:line)
    assert_includes @log.string, 'rejected line 3: unknown store "99 Nowhere Lane, Mordor"'
    assert_includes @log.string, "rows read=9 inserted=1 duplicates=0 rejected=8"
  end

  test "rows repeating an earlier row in the same batch are skipped and counted as duplicates" do
    result = import("duplicates.csv")

    assert_equal [5, 3, 2, 0], [result.rows_read, result.inserted, result.duplicates, result.rejected]
  end

  test "rows repeating a row from an earlier batch are skipped and counted as duplicates" do
    result = import("duplicates.csv", batch_size: 1)

    assert_equal [5, 3, 2, 0], [result.rows_read, result.inserted, result.duplicates, result.rejected]
  end

  test "an in-stock and an out-of-stock check for the same day are both kept" do
    import("duplicates.csv")

    assert_equal [false, true], imported_checks.select { |check| check[1] == "Pony Pale Ale" }.map(&:last)
  end

  test "importing the same file again inserts nothing and counts every row as a duplicate" do
    import("valid.csv")

    result = assert_no_difference("InventoryCheck.count") { import("valid.csv") }

    assert_equal [4, 0, 4, 0], [result.rows_read, result.inserted, result.duplicates, result.rejected]
  end

  test "a file with only a header imports nothing" do
    result = assert_no_difference("InventoryCheck.count") { import("header_only.csv") }

    assert_equal [0, 0, 0, 0], [result.rows_read, result.inserted, result.duplicates, result.rejected]
  end

  test "a file missing a required header is refused before anything is imported" do
    error = assert_raises(InventoryChecks::CsvImporter::MissingHeadersError) { import("missing_date_header.csv") }

    assert_match(/missing_date_header\.csv is missing required headers: Date\z/, error.message)
    assert_empty imported_checks
  end

  test "an empty file is refused as missing every header" do
    error = assert_raises(InventoryChecks::CsvImporter::MissingHeadersError) { import("empty.csv") }

    assert_match(/missing required headers: Address, Product Name, Date, Inventory Present\z/, error.message)
  end

  test "a file that breaks partway through leaves no rows behind" do
    assert_raises(CSV::MalformedCSVError) { import("malformed.csv", batch_size: 1) }

    assert_empty imported_checks
  end

  test "a leading byte order mark is not mistaken for part of the first header" do
    result = import("byte_order_mark.csv")

    assert_equal 1, result.inserted
  end

  # The delivered data file (inventory_checks.csv) uses CRLF; the excerpt below is stored with LF by git.
  test "a file with Windows line endings imports like any other" do
    Tempfile.create(%w[windows_line_endings .csv]) do |file|
      file.write(file_fixture("inventory_checks/valid.csv").read.gsub("\n", "\r\n"))
      file.close

      result = InventoryChecks::CsvImporter.new(file.path, logger: Logger.new(@log)).import

      assert_equal [4, 4, 0, 0], [result.rows_read, result.inserted, result.duplicates, result.rejected]
    end
  end

  test "an excerpt of the delivered data file imports with its UTF-8 store and product names" do
    create_catalog_from_tracking_events_excerpt

    result = import("tracking_events_excerpt.csv")

    assert_equal [3, 3, 0, 0], [result.rows_read, result.inserted, result.duplicates, result.rejected]
    assert_includes imported_checks,
                    ["135 Strickland Propane Road, Arlen, Texas", "Nobleman’s Wine Reserve",
                     Time.zone.local(2025, 9, 16), true]
    assert_includes imported_checks,
                    ["9¾ Platform Plaza, King’s Cross, Wizarding World", "Corporate Security Drones",
                     Time.zone.local(2025, 2, 22), false]
  end

  test "an explicit source path is used even when the default files exist" do
    in_app_root_with("inventory_checks.csv", "tracking_events.csv", "elsewhere.csv") do |root|
      explicit_path = root.join("elsewhere.csv")

      assert_equal explicit_path, InventoryChecks::CsvImporter.locate_source(explicit_path, root:)
    end
  end

  test "an explicit source path that doesn't exist is reported, without falling back to the defaults" do
    in_app_root_with("inventory_checks.csv") do |root|
      error = assert_raises(InventoryChecks::CsvImporter::SourceNotFoundError) do
        InventoryChecks::CsvImporter.locate_source(root.join("missing.csv"), root:)
      end

      assert_equal "No inventory checks CSV found. Looked for:\n  #{root.join('missing.csv')}", error.message
    end
  end

  test "without a path, inventory_checks.csv in the app root is preferred over tracking_events.csv" do
    in_app_root_with("inventory_checks.csv", "tracking_events.csv") do |root|
      assert_equal root.join("inventory_checks.csv"), InventoryChecks::CsvImporter.locate_source(root:)
    end
  end

  test "without a path or inventory_checks.csv, the legacy tracking_events.csv is used" do
    in_app_root_with("tracking_events.csv") do |root|
      assert_equal root.join("tracking_events.csv"), InventoryChecks::CsvImporter.locate_source(root:)
    end
  end

  test "with no source file at all, both default paths are reported" do
    in_app_root_with do |root|
      error = assert_raises(InventoryChecks::CsvImporter::SourceNotFoundError) do
        InventoryChecks::CsvImporter.locate_source(root:)
      end

      assert_equal <<~MESSAGE.chomp, error.message
        No inventory checks CSV found. Looked for:
          #{root.join('inventory_checks.csv')}
          #{root.join('tracking_events.csv')}
      MESSAGE
    end
  end

  test "an import reconciles the alerts of every pair it added checks to" do
    split_streak = inventory_alerts(:porter_out_at_hobbiton)

    result = import("alert_changes.csv")

    assert_equal alert_counts(1, 1, 1), result.derived_records
    assert_equal [inventory_checks(:pale_ale_sold_out_at_bree)],
                 InventoryAlert.where(store: stores(:bree_high_street)).map(&:streak_start_check)
    assert_equal Time.zone.local(2025, 1, 5), inventory_alerts(:stout_out_at_hobbiton).reload.resolved_at
    assert_not InventoryAlert.exists?(split_streak.id)
  end

  test "the import summary includes the alert changes" do
    result = import("alert_changes.csv")

    assert_equal "rows read=3 inserted=3 duplicates=0 rejected=0; alerts created=1 updated=1 deleted=1", result.summary
  end

  test "importing the same file again changes no alerts" do
    import("alert_changes.csv")

    assert_equal alert_counts(0, 0, 0), import("alert_changes.csv").derived_records
  end

  # Would fail if every parsed row's pair were reconciled, not just the inserted ones.
  test "pairs whose rows were all duplicates are not reconciled" do
    import("alert_changes.csv")
    stale = InventoryAlert.find_by!(store: stores(:bree_high_street))
    stale.update!(miss_count: 7)

    import("alert_changes.csv")

    assert_equal 7, stale.reload.miss_count
  end

  test "a file that breaks partway through leaves the alerts as they were" do
    alerts_before = InventoryAlert.order(:id).map(&:attributes)

    assert_raises(CSV::MalformedCSVError) { import("malformed_after_alert_changes.csv", batch_size: 1) }

    assert_equal alerts_before, InventoryAlert.order(:id).map(&:attributes)
  end

  test "alerts are reconciled inside the import's transaction, so a failure there rolls back the checks too" do
    failing_reconciler = ->(**) { raise ActiveRecord::StatementInvalid, "reconcile failed" }

    InventoryAlerts::Reconciler.stub(:new, failing_reconciler) do
      assert_raises(ActiveRecord::StatementInvalid) { import("alert_changes.csv") }
    end

    assert_empty imported_checks
  end

  private

  def in_app_root_with(*file_names)
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      file_names.each { |name| FileUtils.touch(root.join(name)) }
      yield root
    end
  end

  def import(file_name, batch_size: 5_000)
    InventoryChecks::CsvImporter.new(file_fixture("inventory_checks/#{file_name}"),
                                     batch_size:, logger: Logger.new(@log)).import
  end

  def rejection(line, reason)
    InventoryChecks::CsvImporter::Rejection.new(line:, reason:)
  end

  def alert_counts(created, updated, deleted)
    InventoryAlerts::Reconciler::Result.new(created:, updated:, deleted:)
  end

  # Fixture checks are all from 2024; every file under test is dated 2025.
  def imported_checks
    InventoryCheck.joins(:store, :product).where(event_time: Time.zone.local(2025, 1, 1)..).order(:id)
                  .pluck("stores.address", "products.name", :event_time, :inventory_present)
  end

  def create_catalog_from_tracking_events_excerpt
    ["18 Salamandastron Beach Road, Western Shores", "135 Strickland Propane Road, Arlen, Texas",
     "9¾ Platform Plaza, King’s Cross, Wizarding World"].each { |address| Store.create!(address:) }
    ["Paleo-DNA Sequencing Devices", "Nobleman’s Wine Reserve", "Corporate Security Drones"].each do |name|
      Product.create!(name:, brand: brands(:prancing_pony))
    end
  end
end
