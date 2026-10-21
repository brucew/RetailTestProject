require "test_helper"

class InventoryAlerts::ReconcilerTest < ActiveSupport::TestCase
  # Bree has no fixture checks for Dragon Stout, so each test builds the
  # pair's whole timeline itself. Checks are recorded in arrival order, which
  # is also id order; the dates say where each belongs on the timeline.
  setup do
    @store = stores(:bree_high_street)
    @product = products(:dragon_stout)
  end

  test "a single miss raises no alert" do
    miss("2025-01-01")

    assert_equal result(0, 0, 0), reconcile
    assert_empty alerts
  end

  test "a second consecutive miss raises one open alert for the product's brand" do
    hit("2025-01-01")
    first_miss = miss("2025-01-02")
    second_miss = miss("2025-01-03")

    assert_equal result(1, 0, 0), reconcile
    assert_alerts [{ streak_start_check: first_miss, triggering_check: second_miss, resolving_check: nil,
                     started_at: day("2025-01-02"), triggered_at: day("2025-01-03"), resolved_at: nil,
                     miss_count: 2, brand: brands(:green_dragon) }]
  end

  test "further misses extend the same alert rather than raising another" do
    first_miss = miss("2025-01-01")
    second_miss = miss("2025-01-02")
    reconcile

    miss("2025-01-03")
    miss("2025-01-04")

    assert_equal result(0, 1, 0), reconcile
    assert_alerts [{ streak_start_check: first_miss, triggering_check: second_miss, miss_count: 4 }]
  end

  test "inventory seen again resolves the alert with that check" do
    miss("2025-01-01")
    miss("2025-01-02")
    reconcile

    restock = hit("2025-01-03")

    assert_equal result(0, 1, 0), reconcile
    assert_alerts [{ resolving_check: restock, resolved_at: day("2025-01-03"), miss_count: 2 }]
  end

  test "a new streak after a resolved one raises a second alert" do
    miss("2025-01-01")
    miss("2025-01-02")
    hit("2025-01-03")
    reconcile

    hit("2025-01-04")
    next_miss = miss("2025-01-05")
    miss("2025-01-06")

    assert_equal result(1, 0, 0), reconcile
    assert_alerts [{ started_at: day("2025-01-01"), resolved_at: day("2025-01-03") },
                   { streak_start_check: next_miss, started_at: day("2025-01-05"), resolved_at: nil }]
  end

  # Would fail with MIN(id): the streak's first check by time has the higher id.
  test "a late miss dated before a lone miss starts a streak at the earlier check" do
    lone_miss = miss("2025-01-02")
    reconcile

    late_miss = miss("2025-01-01")

    assert_equal result(1, 0, 0), reconcile
    assert_alerts [{ streak_start_check: late_miss, triggering_check: lone_miss,
                     started_at: day("2025-01-01"), triggered_at: day("2025-01-02") }]
  end

  # Would fail if the timeline were ordered by id: the restock arrived first.
  test "checks are ordered by event time, not by when they arrived" do
    restock = hit("2025-01-03")
    first_miss = miss("2025-01-01")
    miss("2025-01-02")

    reconcile

    assert_alerts [{ streak_start_check: first_miss, resolving_check: restock, miss_count: 2 }]
  end

  test "a late earlier miss moves the streak's start, replacing its alert" do
    miss("2025-01-02")
    miss("2025-01-03")
    reconcile
    moved_from = alerts.sole

    earlier_miss = miss("2025-01-01")

    assert_equal result(1, 0, 1), reconcile
    assert_not InventoryAlert.exists?(moved_from.id)
    assert_alerts [{ streak_start_check: earlier_miss, triggering_check: moved_from.streak_start_check,
                     miss_count: 3 }]
  end

  test "a late in-stock check between the only two misses removes the alert" do
    miss("2025-01-01")
    miss("2025-01-02")
    reconcile

    hit(Time.zone.parse("2025-01-01 12:00"))

    assert_equal result(0, 0, 1), reconcile
    assert_empty alerts
  end

  test "a late in-stock check in the middle of a long streak splits it into two alerts" do
    first_miss = miss("2025-01-01")
    miss("2025-01-02")
    third_miss = miss("2025-01-03")
    miss("2025-01-04")
    reconcile

    late_restock = hit(Time.zone.parse("2025-01-02 12:00"))

    assert_equal result(1, 1, 0), reconcile
    assert_alerts [{ streak_start_check: first_miss, resolving_check: late_restock, miss_count: 2 },
                   { streak_start_check: third_miss, resolving_check: nil, miss_count: 2 }]
  end

  # Same-day checks keep CSV order, which is id order (D6).
  test "a same-day restock recorded after the miss resolves the streak" do
    miss("2025-01-01")
    miss("2025-01-02")
    same_day_restock = hit("2025-01-02")

    reconcile

    assert_alerts [{ resolving_check: same_day_restock, resolved_at: day("2025-01-02"), miss_count: 2 }]
  end

  test "a same-day miss recorded after the restock continues into a new run" do
    miss("2025-01-01")
    hit("2025-01-02")
    miss("2025-01-02")

    reconcile

    assert_empty alerts
  end

  test "in-stock checks for another product at the store, or the product at another store, don't break a streak" do
    first_miss = miss("2025-01-01")
    InventoryCheck.create!(store: @store, product: products(:pony_porter), event_time: day("2025-01-02"),
                           inventory_present: true)
    InventoryCheck.create!(store: stores(:hobbiton_bywater_road), product: @product, event_time: day("2025-01-02"),
                           inventory_present: true)
    miss("2025-01-03")

    reconcile(pairs: [[@store.id, @product.id], [@store.id, products(:pony_porter).id],
                      [stores(:hobbiton_bywater_road).id, @product.id]])

    assert_alerts [{ streak_start_check: first_miss, miss_count: 2 }]
  end

  test "an alert follows its product to a new brand" do
    miss("2025-01-01")
    miss("2025-01-02")
    reconcile

    @product.update!(brand: brands(:prancing_pony))

    assert_equal result(0, 1, 0), reconcile
    assert_alerts [{ brand: brands(:prancing_pony) }]
  end

  test "reconciling again changes nothing and leaves alerts as they were" do
    miss("2025-01-01")
    miss("2025-01-02")
    hit("2025-01-03")
    reconcile
    written = alerts.pluck(:id, :updated_at)

    assert_equal result(0, 0, 0), reconcile
    assert_equal written, alerts.pluck(:id, :updated_at)
  end

  test "only the listed pairs are reconciled, even when other pairs' alerts are out of date" do
    stale = inventory_alerts(:stout_out_at_hobbiton)
    stale.update!(miss_count: 7)
    InventoryCheck.create!(store: @store, product: products(:pony_porter), event_time: day("2025-01-01"),
                           inventory_present: false)
    miss("2025-01-01")
    miss("2025-01-02")

    assert_equal result(1, 0, 0), reconcile

    assert_equal 7, stale.reload.miss_count
    assert_equal 3, InventoryAlert.count
  end

  test "reconciling one pair leaves other products' alerts at the same store alone" do
    hobbiton = stores(:hobbiton_bywater_road)
    stale = inventory_alerts(:stout_out_at_hobbiton)
    stale.update!(miss_count: 7)

    assert_equal result(0, 0, 0), reconcile(pairs: [[hobbiton.id, products(:pony_pale_ale).id]])

    assert_equal 7, stale.reload.miss_count
    assert_equal 2, hobbiton.inventory_alerts.count
  end

  test "an empty list of pairs reconciles nothing, not everything" do
    inventory_alerts(:stout_out_at_hobbiton).update!(miss_count: 7)
    miss("2025-01-01")
    miss("2025-01-02")

    assert_equal result(0, 0, 0), reconcile(pairs: [])
    assert_empty alerts
  end

  test "a full reconcile of the fixture checks changes nothing, so the fixtures are what it derives" do
    assert_equal result(0, 0, 0), reconcile(pairs: nil)
    assert_equal 2, InventoryAlert.count
  end

  test "a full reconcile restores missing alerts, corrects changed ones and removes unsupported ones" do
    inventory_alerts(:porter_out_at_hobbiton).destroy!
    inventory_alerts(:stout_out_at_hobbiton).update!(miss_count: 7)
    bree_miss = inventory_checks(:pale_ale_sold_out_at_bree)
    InventoryAlert.create!(brand: brands(:prancing_pony), store: bree_miss.store, product: bree_miss.product,
                           streak_start_check: bree_miss, triggering_check: bree_miss,
                           started_at: bree_miss.event_time, triggered_at: bree_miss.event_time, miss_count: 2)

    assert_equal result(1, 1, 1), reconcile(pairs: nil)
    assert_equal [2, 2], InventoryAlert.order(:started_at).pluck(:miss_count)
    assert_equal [inventory_checks(:stout_sold_out_at_hobbiton), inventory_checks(:porter_sold_out_at_hobbiton)],
                 InventoryAlert.order(:started_at).map(&:streak_start_check)
  end

  # Seq scans are disabled because on a handful of fixture rows Postgres
  # would rightly prefer them; the question is whether the index can be used.
  test "a scoped reconcile reads only the listed pairs' checks, and their stores' alerts, by index" do
    checks_plan = without_seq_scans { explain(captured_query(/scoped_pairs/) { reconcile }) }
    alerts_plan = without_seq_scans { InventoryAlert.where(store_id: [@store.id]).explain.inspect }

    checks_lookup = "Index Scan using index_inventory_checks_on_store_product_time_presence on inventory_checks"
    assert_match(/#{checks_lookup}\b.*\n\s*Index Cond: \(\(store_id = pair\.store_id\) AND \(product_id = pair\.product_id\)\)/,
                 checks_plan)
    assert_match(/index_inventory_alerts_on_store_id_and_product_id.*\n\s*Index Cond: \(store_id = /, alerts_plan)
  end

  test "reconciling every pair of an import reads alerts without one OR term per pair" do
    other_store = Store.create!(address: "3 Market Square, Michel Delving")
    pairs = [[@store.id, @product.id], [other_store.id, @product.id]]

    alert_reads = capture_sql_queries { reconcile(pairs:) }.grep(/FROM "inventory_alerts"/)

    assert_equal 1, alert_reads.size
    assert_no_match(/ OR /, alert_reads.sole)
  end

  test "the result summarizes the counts" do
    assert_equal "alerts created=1 updated=2 deleted=3", result(1, 2, 3).summary
  end

  private

  def miss(on) = record_check(on, inventory_present: false)

  def hit(on) = record_check(on, inventory_present: true)

  def record_check(on, inventory_present:)
    event_time = on.is_a?(String) ? day(on) : on
    InventoryCheck.create!(store: @store, product: @product, event_time:, inventory_present:)
  end

  def day(date) = Time.zone.parse(date)

  def reconcile(pairs: [[@store.id, @product.id]])
    InventoryAlerts::Reconciler.new(pairs:).reconcile
  end

  def result(created, updated, deleted)
    InventoryAlerts::Reconciler::Result.new(created:, updated:, deleted:)
  end

  def alerts
    InventoryAlert.where(store: @store, product: @product).order(:started_at)
  end

  def without_seq_scans
    InventoryAlert.transaction(requires_new: true) do
      InventoryAlert.connection.execute("SET LOCAL enable_seqscan = off")
      yield
    end
  end

  # The one query matching pattern that the block runs, with its bind values.
  def captured_query(pattern, &block)
    queries = []
    capture = ->(*, payload) { queries << payload if payload[:sql].match?(pattern) }
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record", &block)
    queries.sole
  end

  def explain(query)
    InventoryAlert.connection.select_values("EXPLAIN #{query[:sql]}", "EXPLAIN", query[:binds]).join("\n")
  end

  # Compares only the attributes each expectation names, alert by alert in
  # timeline order.
  def assert_alerts(expectations)
    actual = alerts.to_a
    assert_equal expectations.size, actual.size, "number of alerts"
    expectations.zip(actual).each do |expected, alert|
      assert_equal expected, expected.keys.index_with { |attribute| alert.public_send(attribute) }
    end
  end
end
