# Rails 7.1 has no public assert_queries_count (it arrives in 7.2), so pages
# prove their query budgets with this instead.
module QueryAssertions
  # Schema lookups and BEGIN/COMMIT are framework bookkeeping, and cached
  # queries never reach the database, so none of them count against a page.
  IGNORED_QUERY_NAMES = %w[SCHEMA TRANSACTION].freeze

  # Fails when the block runs more than +maximum+ SQL queries, listing every
  # query that ran so the offending N+1 is obvious from the failure message.
  def assert_max_queries(maximum, &)
    queries = capture_sql_queries(&)

    assert queries.size <= maximum,
           "Expected at most #{maximum} queries, but #{queries.size} ran:\n#{queries.join("\n")}"
  end

  # Returns the SQL of every query the block sent to the database.
  def capture_sql_queries
    queries = []
    counter = lambda do |*, payload|
      queries << payload[:sql] unless payload[:cached] || IGNORED_QUERY_NAMES.include?(payload[:name])
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    queries
  end
end
