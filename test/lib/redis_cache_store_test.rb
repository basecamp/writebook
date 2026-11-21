require "test_helper"
require "open3"

class RedisCacheStoreTest < ActiveSupport::TestCase
  test "production's cache store connects to REDIS_URL" do
    env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1", "REDIS_URL" => "redis://redis.example:6390/3" }
    output, status = Open3.capture2e(env, "bin/rails", "runner", "print Rails.cache.redis.with { it.config.server_url }", chdir: Rails.root)

    assert status.success?, output
    assert_equal "redis://redis.example:6390/3", output.lines.last
  end
end
