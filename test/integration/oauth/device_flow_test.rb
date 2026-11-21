require "test_helper"

class Oauth::DeviceFlowTest < ActionDispatch::IntegrationTest
  test "a device signs in through the whole flow" do
    post oauth_device_authorizations_url, params: { client_id: Oauth::CLIENT_ID }
    assert_response :success

    authorization = response.parsed_body
    device_code = authorization["device_code"]
    user_code = authorization["user_code"]
    assert_match(/\Awb_dc_/, device_code)
    assert_match(/\A[A-Z2-9]{4}-[A-Z2-9]{4}\z/, user_code)
    assert_equal oauth_device_verification_url, authorization["verification_uri"]
    assert_equal 5, authorization["interval"]

    poll device_code
    assert_oauth_error :authorization_pending

    travel 6.seconds

    sign_in :david
    get oauth_device_verification_url(user_code: user_code)
    assert_response :success
    assert_select "form input[name=user_code]"

    patch oauth_device_verification_url, params: { user_code: user_code, initiation_confirmed: "1" }
    assert_response :success

    poll device_code
    assert_response :success

    tokens = response.parsed_body
    assert_match(/\Awb_at_/, tokens["access_token"])
    assert_match(/\Awb_rt_/, tokens["refresh_token"])
    assert_equal "Bearer", tokens["token_type"]

    get root_url, headers: { "Authorization" => "Bearer #{tokens["access_token"]}" }
    assert_response :success

    travel 6.seconds
    poll device_code
    assert_oauth_error :invalid_grant
  end

  test "polling too fast answers slow_down" do
    device_code = requested_device_code

    poll device_code
    assert_oauth_error :authorization_pending

    poll device_code
    assert_oauth_error :slow_down
  end

  test "a denied device gets access_denied" do
    device_code = requested_device_code
    grant = Oauth::DeviceGrant.find_by_raw_device_code(device_code)

    sign_in :david
    delete oauth_device_verification_url, params: { user_code: grant.user_code }
    assert_response :success

    poll device_code
    assert_oauth_error :access_denied
  end

  test "an expired device code gets expired_token" do
    device_code = requested_device_code

    travel 11.minutes

    poll device_code
    assert_oauth_error :expired_token
  end

  test "approval requires confirming the sign-in was user-initiated" do
    device_code = requested_device_code
    grant = Oauth::DeviceGrant.find_by_raw_device_code(device_code)

    sign_in :david
    patch oauth_device_verification_url, params: { user_code: grant.user_code }
    assert_response :success
    assert grant.reload.pending?

    travel 6.seconds
    poll device_code
    assert_oauth_error :authorization_pending
  end

  test "verification requires signing in first" do
    get oauth_device_verification_url
    assert_redirected_to new_session_url
  end

  test "an unknown user code is rejected" do
    sign_in :david
    post oauth_device_verification_url, params: { user_code: "XXXX-XXXX" }
    assert_response :unprocessable_entity
  end

  test "an unknown client cannot start the flow" do
    post oauth_device_authorizations_url, params: { client_id: "somebody-else" }
    assert_response :unauthorized
    assert_equal "invalid_client", response.parsed_body["error"]
  end

  private
    def requested_device_code
      post oauth_device_authorizations_url, params: { client_id: Oauth::CLIENT_ID }
      response.parsed_body["device_code"]
    end

    def poll(device_code)
      post oauth_tokens_url, params: {
        client_id: Oauth::CLIENT_ID,
        grant_type: Oauth::DEVICE_CODE_GRANT_TYPE,
        device_code: device_code
      }
    end

    def assert_oauth_error(code)
      assert_response :bad_request
      assert_equal code.to_s, response.parsed_body["error"]
    end
end
