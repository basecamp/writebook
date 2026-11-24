require "test_helper"

class Oauth::AccessTokenTest < ActiveSupport::TestCase
  test "find_active_by_raw_token ignores unknown, expired, revoked and deactivated users' tokens" do
    assert_equal oauth_access_tokens(:davids), Oauth::AccessToken.find_active_by_raw_token(DAVIDS_ACCESS_TOKEN)

    assert_nil Oauth::AccessToken.find_active_by_raw_token("wb_at_unknown")
    assert_nil Oauth::AccessToken.find_active_by_raw_token(DAVIDS_EXPIRED_ACCESS_TOKEN)

    users(:jz).deactivate
    assert_nil Oauth::AccessToken.find_active_by_raw_token(JZS_ACCESS_TOKEN)

    oauth_access_tokens(:davids).update! revoked_at: Time.current
    assert_nil Oauth::AccessToken.find_active_by_raw_token(DAVIDS_ACCESS_TOKEN)
  end
end
