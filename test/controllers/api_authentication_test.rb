require "test_helper"

class ApiAuthenticationTest < ActionDispatch::IntegrationTest
  # The handbook fixture is unpublished, so anonymous requests can't see it
  # and bearer-key requests only can when the key authenticates.

  test "a bearer key authenticates where the controller allows it" do
    get book_slug_path(books(:handbook)), headers: bearer_key_header(:david)

    assert_response :success
  end

  test "a bearer key works without a session cookie or CSRF token" do
    get book_slug_path(books(:handbook)), headers: bearer_key_header(:jz)

    assert_response :success
    assert_not cookies[:session_token].present?
  end

  test "a bad key stays anonymous" do
    get book_slug_path(books(:handbook)), headers: { "Authorization" => "Bearer wrong" }

    assert_response :not_found
  end

  test "a reset key stops working" do
    old_key = users(:david).bearer_key
    users(:david).regenerate_bearer_key

    get book_slug_path(books(:handbook)), headers: { "Authorization" => "Bearer #{old_key}" }

    assert_response :not_found
  end

  test "a deactivated user's key stops working" do
    users(:david).deactivate

    get book_slug_path(books(:handbook)), headers: bearer_key_header(:david)

    assert_response :not_found
  end

  test "a valid key does not authenticate on controllers that haven't opted in" do
    get edit_book_path(books(:handbook)), headers: bearer_key_header(:david)

    assert_response :unauthorized
  end

  test "requests with a key get unauthorized instead of a login redirect" do
    get users_path, headers: bearer_key_header(:david)

    assert_response :unauthorized
  end

  test "browser requests without a key still get the login redirect" do
    get edit_book_path(books(:handbook))

    assert_redirected_to new_session_url
  end
end
