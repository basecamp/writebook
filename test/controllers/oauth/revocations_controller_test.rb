require "test_helper"

class Oauth::RevocationsControllerTest < ActionDispatch::IntegrationTest
  test "revoking a refresh token kills its whole family" do
    post oauth_revocations_url, params: { client_id: Oauth::CLIENT_ID, token: DAVIDS_REFRESH_TOKEN }
    assert_response :success

    assert oauth_refresh_tokens(:davids).reload.revoked?
    assert oauth_access_tokens(:davids).reload.revoked?
  end

  test "revoking an access token leaves the refresh token alone" do
    post oauth_revocations_url, params: { client_id: Oauth::CLIENT_ID, token: DAVIDS_ACCESS_TOKEN }
    assert_response :success

    assert oauth_access_tokens(:davids).reload.revoked?
    assert_not oauth_refresh_tokens(:davids).reload.revoked?
  end

  test "an unknown token still answers 200" do
    post oauth_revocations_url, params: { client_id: Oauth::CLIENT_ID, token: "wb_rt_nonsense" }
    assert_response :success
  end
end
