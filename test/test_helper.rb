ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/inventory_check_history"
require_relative "support/query_assertions"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include InventoryCheckHistory
    include QueryAssertions

    # The unique index makes exact duplicates impossible, but the cleanup task
    # and the migration guard exist for databases created before it. Dropping
    # the index is DDL, which Postgres rolls back with the test's transaction.
    def allow_duplicate_inventory_checks
      ActiveRecord::Base.connection.remove_index :inventory_checks,
                                                name: "index_inventory_checks_on_store_product_time_presence"
    end
  end
end
