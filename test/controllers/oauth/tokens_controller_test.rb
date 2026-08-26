require "test_helper"

class Oauth::TokensControllerTest < ActionDispatch::IntegrationTest
  test "refreshing rotates the token and mints a new pair" do
    refresh
    assert_response :success

    tokens = response.parsed_body
    assert_match(/\Awb_at_/, tokens["access_token"])
    assert_match(/\Awb_rt_/, tokens["refresh_token"])
    assert_not_equal DAVIDS_REFRESH_TOKEN, tokens["refresh_token"]

    assert oauth_refresh_tokens(:davids).reload.rotated?
    assert_equal oauth_refresh_tokens(:davids).family_id,
      Oauth::RefreshToken.find_by_raw_token(tokens["refresh_token"]).family_id
  end

  test "replaying a refresh inside the grace window returns the same successor" do
    refresh
    first = response.parsed_body

    refresh
    assert_response :success
    assert_equal first["refresh_token"], response.parsed_body["refresh_token"]
  end

  test "replaying a refresh after the grace window revokes the whole family" do
    refresh
    successor_raw_token = response.parsed_body["refresh_token"]

    travel 2.minutes

    refresh
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]

    assert Oauth::RefreshToken.find_by_raw_token(successor_raw_token).revoked?
    assert oauth_access_tokens(:davids).reload.revoked?
  end

  test "an expired refresh token is rejected" do
    oauth_refresh_tokens(:davids).update! expires_at: 1.hour.ago

    refresh
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "unknown grant types are rejected" do
    post oauth_tokens_url, params: { client_id: Oauth::CLIENT_ID, grant_type: "authorization_code" }
    assert_response :bad_request
    assert_equal "unsupported_grant_type", response.parsed_body["error"]
  end

  test "an unrecognized client is rejected" do
    post oauth_tokens_url, params: { client_id: "somebody-else", grant_type: "refresh_token", refresh_token: DAVIDS_REFRESH_TOKEN }
    assert_response :unauthorized
  end

  private
    def refresh(token = DAVIDS_REFRESH_TOKEN)
      post oauth_tokens_url, params: { client_id: Oauth::CLIENT_ID, grant_type: "refresh_token", refresh_token: token }
    end
end
