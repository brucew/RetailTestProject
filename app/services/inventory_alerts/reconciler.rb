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
    #         reconciles every pair; an empty list reconciles none. Ids are
    #         read as integers and repeats dropped: a repeated pair would join
    #         its checks twice, and stored alerts are matched by integer ids.
    def initialize(pairs: nil)
      @pairs = pairs&.map { |store_id, product_id| [Integer(store_id), Integer(product_id)] }&.uniq
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
      streaks.pluck(*streak_columns.values).to_h do |values|
        alert = streak_columns.keys.zip(values).to_h
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
      # insert_all! raises rather than skipping a conflict, so a new alert that
      # somehow already exists fails the reconcile instead of being miscounted.
      InventoryAlert.insert_all!(created) if created.any?
      InventoryAlert.upsert_all(changed, unique_by: :streak_start_check_id) if changed.any?
      InventoryAlert.where(streak_start_check_id: stale_start_check_ids).delete_all if stale_start_check_ids.any?
    end

    # Each alert attribute and the streak column it's read from.
    def streak_columns
      {
        "brand_id" => "products.brand_id", "store_id" => :store_id, "product_id" => :product_id,
        "streak_start_check_id" => :first_check_id, "triggering_check_id" => :second_check_id,
        "resolving_check_id" => :next_run_first_check_id, "started_at" => :first_event_time,
        "triggered_at" => :second_event_time, "resolved_at" => :next_run_started_at, "miss_count" => :check_count
      }
    end

    # The streak queries below nest each step as a subquery aliased
    # "inventory_checks", so ActiveRecord's own column handling (group, where,
    # joins(:product)) applies to it. SQL appears only for expressions
    # ActiveRecord can't build: window functions, FILTER and ordered
    # aggregates.

    # Out-of-stock runs of two or more checks: the alerts the checks imply,
    # raised at the second miss (D5) and addressed to the product's brand (A9).
    def streaks
      InventoryCheck.from(runs_with_next, :inventory_checks).joins(:product)
                    .where(in_stock: false, check_count: 2..)
    end

    # Runs alternate, so the run after a stockout is the restock that resolves
    # it; a timeline's last run has none.
    def runs_with_next
      InventoryCheck.from(runs, :inventory_checks)
                    .select("inventory_checks.*",
                            "LEAD(first_check_id) OVER (#{run_sequence}) AS next_run_first_check_id",
                            "LEAD(first_event_time) OVER (#{run_sequence}) AS next_run_started_at")
    end

    # One row per run of consecutive checks with the same result. Its first two
    # checks are taken in timeline order, not by id (D6).
    def runs
      InventoryCheck.from(numbered_checks, :inventory_checks)
                    .group(:store_id, :product_id, :run_number)
                    .select(:store_id, :product_id, :run_number,
                            "bool_and(inventory_present) AS in_stock", "COUNT(*) AS check_count",
                            "(ARRAY_AGG(id ORDER BY event_time, id))[1] AS first_check_id",
                            "(ARRAY_AGG(id ORDER BY event_time, id))[2] AS second_check_id",
                            "MIN(event_time) AS first_event_time",
                            "(ARRAY_AGG(event_time ORDER BY event_time, id))[2] AS second_event_time")
    end

    # A running count of run starts numbers each check's run.
    def numbered_checks
      InventoryCheck.from(timeline, :inventory_checks)
                    .select("inventory_checks.*", "COUNT(*) FILTER (WHERE starts_run) OVER (#{pair_timeline}) AS run_number")
    end

    # Each check, marked when its result differs from the check before it.
    def timeline
      checks_in_scope.select(:id, :store_id, :product_id, :event_time, :inventory_present,
                             "inventory_present IS DISTINCT FROM LAG(inventory_present) OVER (#{pair_timeline}) AS starts_run")
    end

    # Every check for a full rebuild, else the listed pairs' checks, joined to
    # them as an unnested array. Not where([:store_id, :product_id] => pairs):
    # Rails 7.1 turns that into one OR term per pair, which Postgres can't
    # serve from an index (over 80 s for an import's 22,826 pairs).
    def checks_in_scope
      return InventoryCheck.all if @pairs.nil?

      InventoryCheck.joins("JOIN (#{scoped_pairs_sql}) AS scoped_pairs USING (store_id, product_id)")
    end

    def scoped_pairs_sql
      InventoryCheck.sanitize_sql_array([
        "SELECT * FROM unnest(:store_ids::bigint[], :product_ids::bigint[]) AS pair (store_id, product_id)",
        { store_ids: encode_array(@pairs.map(&:first)), product_ids: encode_array(@pairs.map(&:last)) }
      ])
    end

    # A Postgres array literal ("{1,2}"), bound as a single quoted value.
    def encode_array(ids)
      PG::TextEncoder::Array.new.encode(ids)
    end

    # Each store/product pair's checks in timeline order. Same-day checks are
    # ordered by id (D6); ids alone aren't in time order, because checks
    # arrive out of order.
    def pair_timeline
      "PARTITION BY store_id, product_id ORDER BY event_time, id"
    end

    def run_sequence
      "PARTITION BY store_id, product_id ORDER BY run_number"
    end
  end
end
