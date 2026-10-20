module InventoryAlerts
  # Keeps inventory_alerts consistent with the inventory checks (D7).
  #
  # Alerts are a projection of each store/product timeline: one alert per run
  # of two or more consecutive "no inventory" checks (D5), in (event_time, id)
  # order (D6). Checks can arrive late and out of order, so a new check can
  # start a streak, extend or resolve one, split one in two, or move where one
  # starts. Rather than patch alerts check by check, the reconciler recomputes
  # the alerts the checks imply and makes the table match: it inserts new
  # alerts, updates changed ones and deletes the ones the checks no longer
  # support.
  #
  # Scoped to the pairs whose checks changed, so an import reconciles only the
  # timelines it touched:
  #
  #   InventoryAlerts::Reconciler.new(pairs: [[store_id, product_id]]).reconcile
  #   InventoryAlerts::Reconciler.new.reconcile # every pair: a full rebuild
  class Reconciler
    Result = Data.define(:created, :updated, :deleted) do
      def summary
        "alerts created=#{created} updated=#{updated} deleted=#{deleted}"
      end
    end

    # pairs:: [[store_id, product_id], ...] to reconcile. nil (the default)
    #         reconciles every pair; an empty list reconciles none.
    def initialize(pairs: nil)
      @pairs = pairs
    end

    # Writes only what differs, so reconciling again changes nothing. One
    # statement, so it's atomic on its own and inside a caller's transaction.
    # Returns a Result counting the alerts created, updated and deleted.
    def reconcile
      counts = InventoryAlert.connection.select_one(reconcile_sql, "#{self.class.name} Reconcile")
      Result.new(created: counts.fetch("created"), updated: counts.fetch("updated"), deleted: counts.fetch("deleted"))
    end

    private

    def reconcile_sql
      InventoryAlert.sanitize_sql_array([reconcile_statement, {
        store_ids: encode_array(@pairs.to_a.map(&:first)),
        product_ids: encode_array(@pairs.to_a.map(&:last)),
        now: Time.current
      }])
    end

    # A Postgres array literal ("{1,2}"), bound as a single quoted value.
    def encode_array(ids)
      PG::TextEncoder::Array.new.encode(ids)
    end

    # Which checks and alerts are in scope: all of them for a full rebuild,
    # else those of the listed pairs. This is fixed SQL, never a value. It's
    # chosen here rather than written as one "every pair OR listed pair"
    # condition because Postgres can't turn a subquery under OR into a join:
    # a single-pair reconcile then scans every check (90 ms on the full data,
    # against 1 ms through the unique index).
    def pair_scope
      @pairs.nil? ? "TRUE" : "(store_id, product_id) IN (SELECT store_id, product_id FROM scoped_pairs)"
    end

    def reconcile_statement
      <<~SQL
        WITH scoped_pairs AS (
          SELECT * FROM unnest(:store_ids::bigint[], :product_ids::bigint[]) AS pair (store_id, product_id)
        ),

        -- Each check in timeline order, marked when its result differs from the
        -- check before it. Same-day checks are ordered by id (D6); ids alone
        -- are not in time order, because checks arrive out of order.
        timeline AS (
          SELECT id, store_id, product_id, event_time, inventory_present,
                 inventory_present IS DISTINCT FROM LAG(inventory_present) OVER pair_timeline AS starts_run
          FROM inventory_checks
          WHERE #{pair_scope}
          WINDOW pair_timeline AS (PARTITION BY store_id, product_id ORDER BY event_time, id)
        ),

        -- A running count of run starts numbers the runs of consecutive checks
        -- with the same result.
        numbered_checks AS (
          SELECT *, COUNT(*) FILTER (WHERE starts_run) OVER pair_timeline AS run_number
          FROM timeline
          WINDOW pair_timeline AS (PARTITION BY store_id, product_id ORDER BY event_time, id)
        ),

        -- One row per run. Its first checks are taken in timeline order, not
        -- with MIN(id), for the same reason.
        runs AS (
          SELECT store_id, product_id, run_number,
                 bool_and(inventory_present) AS in_stock,
                 COUNT(*) AS check_count,
                 (ARRAY_AGG(id ORDER BY event_time, id))[1:2] AS first_check_ids,
                 (ARRAY_AGG(event_time ORDER BY event_time, id))[1:2] AS first_event_times
          FROM numbered_checks
          GROUP BY store_id, product_id, run_number
        ),

        -- Runs alternate, so the run after a stockout is the restock that
        -- resolves it; the last run of a timeline has none.
        runs_with_next AS (
          SELECT *,
                 LEAD(first_check_ids[1]) OVER following_run AS next_run_first_check_id,
                 LEAD(first_event_times[1]) OVER following_run AS next_run_started_at
          FROM runs
          WINDOW following_run AS (PARTITION BY store_id, product_id ORDER BY run_number)
        ),

        -- The alerts the checks imply: every out-of-stock run of two or more
        -- checks, raised at its second miss (D5). Addressed to the product's
        -- brand (A9).
        desired_alerts AS (
          SELECT products.brand_id, streaks.store_id, streaks.product_id,
                 streaks.first_check_ids[1] AS streak_start_check_id,
                 streaks.first_check_ids[2] AS triggering_check_id,
                 streaks.next_run_first_check_id AS resolving_check_id,
                 streaks.first_event_times[1] AS started_at,
                 streaks.first_event_times[2] AS triggered_at,
                 streaks.next_run_started_at AS resolved_at,
                 streaks.check_count AS miss_count
          FROM runs_with_next AS streaks
          JOIN products ON products.id = streaks.product_id
          WHERE NOT streaks.in_stock AND streaks.check_count >= 2
        ),

        -- A streak is identified by its first miss. Rows that already match are
        -- skipped, so they keep their updated_at and aren't counted. A fresh
        -- insert has no xmax; an updated row's xmax is this transaction.
        upserted_alerts AS (
          INSERT INTO inventory_alerts (brand_id, store_id, product_id, streak_start_check_id, triggering_check_id,
                                        resolving_check_id, started_at, triggered_at, resolved_at, miss_count,
                                        created_at, updated_at)
          SELECT desired_alerts.*, :now, :now FROM desired_alerts
          ON CONFLICT (streak_start_check_id) DO UPDATE
            SET brand_id = excluded.brand_id, store_id = excluded.store_id, product_id = excluded.product_id,
                triggering_check_id = excluded.triggering_check_id, resolving_check_id = excluded.resolving_check_id,
                started_at = excluded.started_at, triggered_at = excluded.triggered_at,
                resolved_at = excluded.resolved_at, miss_count = excluded.miss_count, updated_at = excluded.updated_at
            WHERE (inventory_alerts.brand_id, inventory_alerts.store_id, inventory_alerts.product_id,
                   inventory_alerts.triggering_check_id, inventory_alerts.resolving_check_id,
                   inventory_alerts.started_at, inventory_alerts.triggered_at, inventory_alerts.resolved_at,
                   inventory_alerts.miss_count)
                  IS DISTINCT FROM
                  (excluded.brand_id, excluded.store_id, excluded.product_id,
                   excluded.triggering_check_id, excluded.resolving_check_id,
                   excluded.started_at, excluded.triggered_at, excluded.resolved_at,
                   excluded.miss_count)
          RETURNING xmax = 0 AS created
        ),

        -- Alerts in scope whose streak the checks no longer contain, e.g. a late
        -- in-stock check that splits it, or a late earlier miss that moves its
        -- start. The upsert never touches these rows, so both can run at once.
        deleted_alerts AS (
          DELETE FROM inventory_alerts
          WHERE #{pair_scope}
            AND streak_start_check_id NOT IN (SELECT streak_start_check_id FROM desired_alerts)
          RETURNING 1
        )

        SELECT (SELECT COUNT(*) FROM upserted_alerts WHERE created) AS created,
               (SELECT COUNT(*) FROM upserted_alerts WHERE NOT created) AS updated,
               (SELECT COUNT(*) FROM deleted_alerts) AS deleted
      SQL
    end
  end
end
