require "test_helper"

class QueryAssertionsTest < ActiveSupport::TestCase
  test "counts each query sent to the database" do
    queries = capture_sql_queries do
      Store.first
      Product.first
    end

    assert_equal 2, queries.size
    assert_match(/FROM "stores"/, queries.first)
  end

  test "ignores transaction and schema bookkeeping" do
    queries = capture_sql_queries do
      Store.transaction { Store.first }
      Store.connection.columns(:stores)
    end

    assert_equal 1, queries.size
  end

  test "ignores queries answered from the query cache" do
    queries = capture_sql_queries do
      Store.cache do
        Store.first
        Store.first
      end
    end

    assert_equal 1, queries.size
  end

  test "passes when the block stays within the budget" do
    assert_max_queries(1) { Store.first }
  end

  test "fails with the offending SQL when the block exceeds the budget" do
    failure = assert_raises(Minitest::Assertion) do
      assert_max_queries(1) { 2.times { |offset| Store.offset(offset).first } }
    end

    assert_match(/at most 1 queries, but 2 ran/, failure.message)
    assert_match(/FROM "stores"/, failure.message)
  end
end
