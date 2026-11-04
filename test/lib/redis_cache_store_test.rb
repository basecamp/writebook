require "test_helper"

class RedisCacheStoreTest < ActiveSupport::TestCase
  test "production's cache store loads" do
    assert_nothing_raised { ActiveSupport::Cache.lookup_store(:redis_cache_store) }
  end
end
