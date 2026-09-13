require "test_helper"

class VersionHelperTest < ActionView::TestCase
  def setup
    @original_app_version = Rails.application.config.app_version
  end

  def teardown
    Rails.application.config.app_version = @original_app_version
  end

  test "version_badge renders the app version in a span" do
    Rails.application.config.app_version = "1.2.0"
    assert_equal '<span class="product__version-badge">1.2.0</span>', version_badge
  end

  test "version_badge renders fallback zero when no version is set" do
    Rails.application.config.app_version = "0"
    assert_equal '<span class="product__version-badge">0</span>', version_badge
  end
end
