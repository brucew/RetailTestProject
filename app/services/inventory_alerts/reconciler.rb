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

    # Writes only what differs, so reconciling again changes nothing. Runs in
    # one transaction (joining a caller's, such as an import's). Returns a
    # Result counting the alerts created, updated and deleted.
    def reconcile
      InventoryAlert.transaction do
        desired = desired_alerts
        stored = stored_alerts
        created = desired.except(*stored.keys)
        changed = desired.slice(*stored.keys).reject { |start_check_id, alert| stored[start_check_id] == alert }
        stale_start_check_ids = stored.keys - desired.keys

        write(created.values, changed.values, stale_start_check_ids)
        Result.new(created: created.size, updated: changed.size, deleted: stale_start_check_ids.size)
      end
    end

    private

    # The attributes the checks determine, keyed by the streak's first check.
    def desired_alerts
      rows = InventoryAlert.connection.select_all(desired_alerts_sql, "#{self.class.name} Desired Alerts")
      rows.cast_values.to_h do |values|
        alert = rows.columns.zip(values).to_h
        [alert.fetch("streak_start_check_id"), alert]
      end
    end

    # The alerts stored for the pairs in scope, in the same shape. Read by
    # store and narrowed to the listed pairs in Ruby: Rails 7.1 turns
    # where([:store_id, :product_id] => pairs) into one OR term per pair,
    # which Postgres can't serve from an index (over 80 s for an import's
    # 22,826 pairs).
    def stored_alerts
      scope = @pairs.nil? ? InventoryAlert.all : InventoryAlert.where(store_id: @pairs.map(&:first).uniq)
      listed = @pairs&.to_set
      scope.pluck(*alert_attributes).each_with_object({}) do |values, alerts|
        alert = alert_attributes.zip(values).to_h
        next if listed && !listed.include?(alert.values_at("store_id", "product_id"))

        alerts[alert.fetch("streak_start_check_id")] = alert
      end
    end

    # Everything on an alert except its own id and timestamps, which Rails sets.
    def alert_attributes
      @alert_attributes ||= InventoryAlert.column_names - %w[id created_at updated_at]
    end

    def write(created, changed, stale_start_check_ids)
      InventoryAlert.insert_all(created) if created.any?
      InventoryAlert.upsert_all(changed, unique_by: :streak_start_check_id) if changed.any?
      InventoryAlert.where(streak_start_check_id: stale_start_check_ids).delete_all if stale_start_check_ids.any?
    end

    def desired_alerts_sql
      InventoryAlert.sanitize_sql_array([desired_alerts_query, {
        store_ids: encode_array(@pairs.to_a.map(&:first)),
        product_ids: encode_array(@pairs.to_a.map(&:last))
      }])
    end

    # A Postgres array literal ("{1,2}"), bound as a single quoted value.
    def encode_array(ids)
      PG::TextEncoder::Array.new.encode(ids)
    end

    # Which checks are in scope: all of them for a full rebuild, else those of
    # the listed pairs. This is fixed SQL, never a value. It's chosen here
    # rather than written as one "every pair OR listed pair" condition because
    # Postgres can't turn a subquery under OR into a join: a single-pair
    # reconcile then scans every check (90 ms on the full data, against 1 ms
    # through the unique index).
    def pair_scope
      @pairs.nil? ? "TRUE" : "(store_id, product_id) IN (SELECT store_id, product_id FROM scoped_pairs)"
    end

    # Window functions find each timeline's runs, which ActiveRecord can't
    # express; this is the one place the reconciler writes SQL.
    def desired_alerts_query
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
        )

        -- The alerts the checks imply: every out-of-stock run of two or more
        -- checks, raised at its second miss (D5). Addressed to the product's
        -- brand (A9).
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
      SQL
    end
  end
end
