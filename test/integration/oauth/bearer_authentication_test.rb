require "test_helper"

class Oauth::BearerAuthenticationTest < ActionDispatch::IntegrationTest
  test "a valid bearer token authenticates without setting a session cookie" do
    get root_url, headers: bearer_headers
    assert_response :success
    assert_not cookies[:session_token].present?
  end

  test "an invalid bearer token answers 401 instead of falling through to the sign-in page" do
    get root_url, headers: bearer_headers("wb_at_nonsense")
    assert_response :unauthorized
    assert_equal 'Bearer error="invalid_token"', response.headers["WWW-Authenticate"]
  end

  test "expired and revoked tokens are rejected" do
    get root_url, headers: bearer_headers(DAVIDS_EXPIRED_ACCESS_TOKEN)
    assert_response :unauthorized

    oauth_access_tokens(:davids).revoke
    get root_url, headers: bearer_headers
    assert_response :unauthorized
  end

  test "bearer requests skip CSRF protection" do
    with_forgery_protection do
      assert_difference -> { Book.count }, +1 do
        post books_url, params: { book: { title: "From the CLI" } }, headers: bearer_headers
      end
    end
  end

  test "cookie-less browser requests still get CSRF protection" do
    with_forgery_protection do
      post session_url, params: { email_address: "david@example.com", password: "secret123456" }
      assert_response :unprocessable_entity
    end
  end

  private
    def with_forgery_protection
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      yield
    ensure
      ActionController::Base.allow_forgery_protection = original
    end
end
