require "test_helper"

class Users::BearerKeysControllerTest < ActionDispatch::IntegrationTest
  test "resetting your own key" do
    sign_in :kevin
    old_key = users(:kevin).bearer_key

    post user_bearer_key_path(users(:kevin))

    assert_redirected_to edit_user_profile_url(users(:kevin))
    assert_not_equal old_key, users(:kevin).reload.bearer_key
  end

  test "a reset key stops authenticating" do
    old_key = users(:david).bearer_key
    sign_in :david

    post user_bearer_key_path(users(:david))
    sign_out

    get book_slug_path(books(:handbook)), headers: { "Authorization" => "Bearer #{old_key}" }
    assert_response :not_found

    get book_slug_path(books(:handbook)), headers: bearer_key_header(users(:david).reload)
    assert_response :success
  end

  test "resetting someone else's key is forbidden" do
    sign_in :david
    old_key = users(:kevin).bearer_key

    post user_bearer_key_path(users(:kevin))

    assert_response :forbidden
    assert_equal old_key, users(:kevin).reload.bearer_key
  end

  test "your key is shown on your own settings, and nobody else's" do
    sign_in :kevin

    get edit_user_profile_path(users(:kevin))

    assert_response :success
    assert_in_body users(:kevin).bearer_key

    get user_profile_path(users(:david))

    assert_response :success
    assert_not_in_body users(:david).bearer_key
  end
end
