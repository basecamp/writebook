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
    assert_equal "read write", tokens["scope"]

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

  test "an unticked confirmation box does not approve" do
    device_code = requested_device_code
    grant = Oauth::DeviceGrant.find_by_raw_device_code(device_code)

    sign_in :david
    patch oauth_device_verification_url, params: { user_code: grant.user_code, initiation_confirmed: "0" }
    assert_response :success
    assert grant.reload.pending?
  end

  test "a bearer token cannot approve or deny a device sign-in, a browser session can" do
    device_code = requested_device_code
    grant = Oauth::DeviceGrant.find_by_raw_device_code(device_code)

    get oauth_device_verification_url(user_code: grant.user_code), headers: bearer_headers
    assert_response :forbidden

    patch oauth_device_verification_url, params: { user_code: grant.user_code, initiation_confirmed: "1" }, headers: bearer_headers
    assert_response :forbidden

    delete oauth_device_verification_url, params: { user_code: grant.user_code }, headers: bearer_headers
    assert_response :forbidden
    assert grant.reload.pending?

    sign_in :david
    patch oauth_device_verification_url, params: { user_code: grant.user_code, initiation_confirmed: "1" }
    assert_response :success
    assert grant.reload.approved?
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

  test "a device without a browser finishes with the approval code it was shown" do
    device_code = requested_device_code
    grant = Oauth::DeviceGrant.find_by_raw_device_code(device_code)

    sign_in :david
    patch oauth_device_verification_url, params: { user_code: grant.user_code, initiation_confirmed: "1" }
    assert_response :success
    approval_code = css_select("#approval_code").text.strip
    assert_match(/\A[A-Z2-9]{4}-[A-Z2-9]{4}\z/, approval_code)

    finish device_code, approval_code.downcase.delete("-")
    assert_response :success
    assert_match(/\Awb_at_/, response.parsed_body["access_token"])

    finish device_code, approval_code
    assert_oauth_error :invalid_grant
  end

  test "a wrong approval code is refused, and the right one still works" do
    device_code = requested_device_code
    grant = Oauth::DeviceGrant.find_by_raw_device_code(device_code)

    sign_in :david
    patch oauth_device_verification_url, params: { user_code: grant.user_code, initiation_confirmed: "1" }
    approval_code = css_select("#approval_code").text.strip

    finish device_code, "AAAA-AAAA"
    assert_oauth_error :invalid_grant

    finish device_code, approval_code
    assert_response :success
  end

  test "an approval code does nothing before approval, after denial or after expiry" do
    device_code = requested_device_code
    grant = Oauth::DeviceGrant.find_by_raw_device_code(device_code)

    finish device_code, "AAAA-AAAA"
    assert_oauth_error :invalid_grant

    sign_in :david
    delete oauth_device_verification_url, params: { user_code: grant.user_code }

    finish device_code, "AAAA-AAAA"
    assert_oauth_error :access_denied

    travel 11.minutes
    finish device_code, "AAAA-AAAA"
    assert_oauth_error :expired_token
  end

  test "a device asking to read only gets a read-only token by polling" do
    post oauth_device_authorizations_url, params: { client_id: Oauth::CLIENT_ID, scope: "read" }
    assert_response :success
    device_code = response.parsed_body["device_code"]
    grant = Oauth::DeviceGrant.find_by_raw_device_code(device_code)

    sign_in :david
    get oauth_device_verification_url(user_code: grant.user_code)
    assert_select "p", text: /will be able to read, but not change/

    patch oauth_device_verification_url, params: { user_code: grant.user_code, initiation_confirmed: "1" }
    poll device_code
    assert_response :success
    tokens = response.parsed_body
    assert_equal "read", tokens["scope"]
    assert Oauth::AccessToken.find_by_raw_token(tokens["access_token"]).read_only?
    assert Oauth::RefreshToken.find_by_raw_token(tokens["refresh_token"]).read_only?

    get books_url(format: :json), headers: bearer_headers(tokens["access_token"])
    assert_response :success

    post books_url, params: { book: { title: "Nope" } }, headers: bearer_headers(tokens["access_token"])
    assert_response :forbidden
  end

  test "a device asking to read only gets a read-only token with the approval code" do
    post oauth_device_authorizations_url, params: { client_id: Oauth::CLIENT_ID, scope: "read" }
    device_code = response.parsed_body["device_code"]
    grant = Oauth::DeviceGrant.find_by_raw_device_code(device_code)

    sign_in :david
    patch oauth_device_verification_url, params: { user_code: grant.user_code, initiation_confirmed: "1" }

    finish device_code, css_select("#approval_code").text.strip
    assert_response :success
    assert_equal "read", response.parsed_body["scope"]
    assert Oauth::AccessToken.find_by_raw_token(response.parsed_body["access_token"]).read_only?
  end

  test "asking for read and write, or for nothing, gets full access" do
    [ "read write", "write", "" ].each do |scope|
      post oauth_device_authorizations_url, params: { client_id: Oauth::CLIENT_ID, scope: scope }
      assert_response :success
      assert_not Oauth::DeviceGrant.find_by_raw_device_code(response.parsed_body["device_code"]).read_only?
    end

    sign_in :david
    get oauth_device_verification_url(user_code: Oauth::DeviceGrant.last.user_code)
    assert_select "p", text: /will get full access/
  end

  test "an unknown or malformed scope is refused" do
    [ "read admin", "read\twrite", "\t", "read  write", " read" ].each do |scope|
      assert_no_difference -> { Oauth::DeviceGrant.count } do
        post oauth_device_authorizations_url, params: { client_id: Oauth::CLIENT_ID, scope: scope }
      end

      assert_oauth_error :invalid_scope
    end
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

    def finish(device_code, approval_code)
      post oauth_tokens_url, params: {
        client_id: Oauth::CLIENT_ID,
        grant_type: Oauth::DEVICE_CODE_GRANT_TYPE,
        device_code: device_code,
        approval_code: approval_code
      }
    end

    def assert_oauth_error(code)
      assert_response :bad_request
      assert_equal code.to_s, response.parsed_body["error"]
    end
end
