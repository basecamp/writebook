require "test_helper"

class Users::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "show" do
    sign_in :david

    get user_profile_url(users(:david))
    assert_response :success

    get user_profile_url(users(:kevin))
    assert_response :success
  end

  test "edit is accessable to the current user" do
    sign_in :david

    get edit_user_profile_url(users(:david))
    assert_response :success

    get edit_user_profile_url(users(:kevin))
    assert_response :forbidden
  end

  test "update modifies profile for current user" do
    sign_in :kevin

    put user_profile_url(users(:kevin)), params: { user: { name: "Bob" } }

    assert_redirected_to users_url
    assert_equal "Bob", users(:kevin).reload.name
  end

  test "update prohibits modifying profile of other users" do
    sign_in :david

    put user_profile_url(users(:kevin)), params: { user: { name: "Bob" } }

    assert_response :forbidden
    assert_equal "Kevin", users(:kevin).reload.name
  end

  test "edit as JSON" do
    get edit_user_profile_url(users(:david), format: :json), headers: bearer_headers

    assert_response :success
    assert_equal({ "id" => users(:david).id, "name" => "David", "email_address" => "david@example.com" }, response.parsed_body)
  end

  test "edit and update as JSON refuse another user's profile" do
    get edit_user_profile_url(users(:kevin), format: :json), headers: bearer_headers
    assert_response :forbidden

    patch user_profile_url(users(:kevin), format: :json), headers: bearer_headers, params: { user: { name: "Bob" } }
    assert_response :forbidden
    assert_equal "Kevin", users(:kevin).reload.name
  end

  test "read-only tokens can't edit or update a profile" do
    [ KEVINS_API_TOKEN, KEVINS_READ_ONLY_ACCESS_TOKEN ].each do |token|
      get edit_user_profile_url(users(:kevin), format: :json), headers: bearer_headers(token)
      assert_response :forbidden

      patch user_profile_url(users(:kevin), format: :json), headers: bearer_headers(token), params: { user: { name: "Bob" } }
      assert_response :forbidden
    end

    assert_equal "Kevin", users(:kevin).reload.name
  end

  test "update as JSON changes the name without the current password" do
    patch user_profile_url(users(:david), format: :json), headers: bearer_headers, params: { user: { name: "Dave", email_address: "david@example.com" } }

    assert_response :success
    assert_equal({ "id" => users(:david).id, "name" => "Dave", "email_address" => "david@example.com" }, response.parsed_body)
    assert_equal "Dave", users(:david).reload.name
  end

  test "update as JSON changes the email address and password with the current password" do
    patch user_profile_url(users(:david), format: :json), headers: bearer_headers,
      params: { user: { email_address: "dave@example.com", password: "newsecret123456", current_password: "secret123456" } }

    assert_response :success
    assert_equal "dave@example.com", response.parsed_body["email_address"]
    assert_equal "dave@example.com", users(:david).reload.email_address
    assert users(:david).authenticate("newsecret123456")
  end

  test "update as JSON refuses to change the email address or password without the right current password" do
    [ nil, "wrong" ].each do |current_password|
      [ { email_address: "dave@example.com" }, { password: "newsecret123456" } ].each do |change|
        patch user_profile_url(users(:david), format: :json), headers: bearer_headers,
          params: { user: { name: "Dave", current_password: current_password, **change } }

        assert_response :unprocessable_entity
        assert_equal [ "Current password is needed to change the email address or password, or it's wrong" ], response.parsed_body["errors"]
      end
    end

    users(:david).reload
    assert_equal "David", users(:david).name
    assert_equal "david@example.com", users(:david).email_address
    assert users(:david).authenticate("secret123456")
  end

  test "update in a browser session changes the email address and password without the current password" do
    sign_in :kevin

    put user_profile_url(users(:kevin)), params: { user: { email_address: "kev@example.com", password: "newsecret123456" } }

    assert_redirected_to users_url
    assert_equal "kev@example.com", users(:kevin).reload.email_address
    assert users(:kevin).authenticate("newsecret123456")
  end

  test "update as JSON answers validation failures with their messages" do
    patch user_profile_url(users(:david), format: :json), headers: bearer_headers, params: { user: { name: "" } }

    assert_response :unprocessable_entity
    assert_equal [ "Name can't be blank" ], response.parsed_body["errors"]
    assert_equal "David", users(:david).reload.name

    patch user_profile_url(users(:david), format: :json), headers: bearer_headers, params: { user: { name: "Kevin" } }

    assert_response :unprocessable_entity
    assert_equal [ "Name or email address is already taken" ], response.parsed_body["errors"]
    assert_equal "David", users(:david).reload.name
  end

  test "the session transfer link is shown to a browser session only" do
    sign_in :david

    get edit_user_profile_url(users(:david))
    assert_select "#session_transfer_url"
    assert_includes response.body, "/session/transfers/"

    get user_profile_url(users(:kevin))
    assert_select "#session_transfer_url"
    assert_includes response.body, "/session/transfers/"

    sign_out

    get edit_user_profile_url(users(:david)), headers: bearer_headers
    assert_response :success
    assert_select "#session_transfer_url", count: 0
    assert_not_includes response.body, "/session/transfers/"

    get user_profile_url(users(:kevin)), headers: bearer_headers
    assert_response :success
    assert_select "#session_transfer_url", count: 0
    assert_not_includes response.body, "/session/transfers/"
  end
end
