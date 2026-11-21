require "test_helper"

class Users::ApiTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "settings list the user's tokens" do
    get edit_user_profile_path(users(:kevin))

    assert_response :success
    assert_in_body "On-call agent"
    assert_in_body "never used"
  end

  test "create shows the new token once and stores only its digest" do
    assert_difference -> { users(:kevin).api_tokens.count }, +1 do
      post user_api_tokens_path(users(:kevin)), params: { api_token: { name: "Runbook reader" } }
    end

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]

    raw_token = response.body[/wb_api_\h{64}/]
    assert raw_token
    assert_equal "Runbook reader", ApiToken.find_by_raw_token(raw_token).name
    assert_nil ApiToken.find_by(token_digest: raw_token)
  end

  test "create names a token left unnamed" do
    post user_api_tokens_path(users(:kevin)), params: { api_token: { name: " " } }

    assert_response :success
    assert_equal "API token", users(:kevin).api_tokens.ordered.first.name
  end

  test "destroy revokes the token" do
    assert_difference -> { ApiToken.count }, -1 do
      delete user_api_token_path(users(:kevin), api_tokens(:kevins))
    end

    assert_redirected_to edit_user_profile_url(users(:kevin))
  end

  test "users can't create or revoke someone else's tokens" do
    sign_in :david

    assert_no_difference -> { ApiToken.count } do
      post user_api_tokens_path(users(:kevin)), params: { api_token: { name: "Not mine" } }
      assert_response :forbidden

      delete user_api_token_path(users(:kevin), api_tokens(:kevins))
      assert_response :forbidden
    end
  end
end
